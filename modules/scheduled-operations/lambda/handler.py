"""
Scheduled Stop/Start Lambda for Ajyal LMS Infrastructure
Manages ASGs, EC2 instances (RabbitMQ), and RDS instances
"""

import boto3
import json
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'preprod')
REGION = os.environ.get('AWS_REGION', 'eu-west-1')

# Initialize clients
autoscaling = boto3.client('autoscaling', region_name=REGION)
ec2 = boto3.client('ec2', region_name=REGION)
rds = boto3.client('rds', region_name=REGION)


# ASG configurations with their normal running capacities
ASG_CONFIGS = {
    f'{ENVIRONMENT}-ajyal-app-asg': {'min': 2, 'max': 20, 'desired': 2},
    f'{ENVIRONMENT}-ajyal-api-asg': {'min': 2, 'max': 10, 'desired': 2},
    f'{ENVIRONMENT}-ajyal-integration-asg': {'min': 2, 'max': 10, 'desired': 2},
    f'{ENVIRONMENT}-ajyal-logging-asg': {'min': 2, 'max': 4, 'desired': 2},
    f'{ENVIRONMENT}-ajyal-botpress-asg': {'min': 2, 'max': 3, 'desired': 2},
    f'{ENVIRONMENT}-ajyal-ml-asg': {'min': 2, 'max': 4, 'desired': 2},
    f'{ENVIRONMENT}-ajyal-content-asg': {'min': 2, 'max': 8, 'desired': 2},
}


def get_rabbitmq_instance_id():
    """Get RabbitMQ EC2 instance ID by tag name"""
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Name', 'Values': [f'{ENVIRONMENT}-ajyal-rabbitmq']},
            {'Name': 'instance-state-name', 'Values': ['running', 'stopped']}
        ]
    )

    for reservation in response.get('Reservations', []):
        for instance in reservation.get('Instances', []):
            return instance['InstanceId']
    return None


def get_rds_instances():
    """Get all RDS instances matching the environment pattern"""
    instances = []
    paginator = rds.get_paginator('describe_db_instances')

    for page in paginator.paginate():
        for db in page['DBInstances']:
            if f'{ENVIRONMENT}-ajyal' in db['DBInstanceIdentifier']:
                instances.append({
                    'id': db['DBInstanceIdentifier'],
                    'status': db['DBInstanceStatus'],
                    'is_cluster_member': 'DBClusterIdentifier' in db
                })
    return instances


def get_rds_clusters():
    """Get all RDS Aurora clusters matching the environment pattern"""
    clusters = []
    paginator = rds.get_paginator('describe_db_clusters')

    for page in paginator.paginate():
        for cluster in page['DBClusters']:
            if f'{ENVIRONMENT}-ajyal' in cluster['DBClusterIdentifier']:
                clusters.append({
                    'id': cluster['DBClusterIdentifier'],
                    'status': cluster['Status']
                })
    return clusters


def stop_services():
    """Stop all services: ASGs, RabbitMQ EC2, and RDS instances"""
    results = {
        'asgs': [],
        'ec2': [],
        'rds_instances': [],
        'rds_clusters': [],
        'errors': []
    }

    # 1. Scale down ASGs to 0
    logger.info("Scaling down ASGs...")
    for asg_name in ASG_CONFIGS.keys():
        try:
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                MinSize=0,
                MaxSize=0,
                DesiredCapacity=0
            )
            results['asgs'].append({'name': asg_name, 'action': 'scaled_to_0', 'status': 'success'})
            logger.info(f"Scaled down ASG: {asg_name}")
        except autoscaling.exceptions.ClientError as e:
            if 'AutoScalingGroupNotFound' in str(e):
                logger.warning(f"ASG not found: {asg_name}")
                results['asgs'].append({'name': asg_name, 'action': 'scaled_to_0', 'status': 'not_found'})
            else:
                logger.error(f"Error scaling ASG {asg_name}: {e}")
                results['errors'].append({'resource': asg_name, 'error': str(e)})
        except Exception as e:
            logger.error(f"Error scaling ASG {asg_name}: {e}")
            results['errors'].append({'resource': asg_name, 'error': str(e)})

    # 2. Stop RabbitMQ EC2 instance
    logger.info("Stopping RabbitMQ EC2 instance...")
    rabbitmq_id = get_rabbitmq_instance_id()
    if rabbitmq_id:
        try:
            # Check current state
            response = ec2.describe_instances(InstanceIds=[rabbitmq_id])
            state = response['Reservations'][0]['Instances'][0]['State']['Name']

            if state == 'running':
                ec2.stop_instances(InstanceIds=[rabbitmq_id])
                results['ec2'].append({'id': rabbitmq_id, 'name': 'rabbitmq', 'action': 'stopped', 'status': 'success'})
                logger.info(f"Stopped RabbitMQ instance: {rabbitmq_id}")
            else:
                results['ec2'].append({'id': rabbitmq_id, 'name': 'rabbitmq', 'action': 'already_stopped', 'status': 'skipped'})
                logger.info(f"RabbitMQ instance already stopped: {rabbitmq_id}")
        except Exception as e:
            logger.error(f"Error stopping RabbitMQ: {e}")
            results['errors'].append({'resource': 'rabbitmq', 'error': str(e)})
    else:
        logger.warning("RabbitMQ instance not found")
        results['ec2'].append({'name': 'rabbitmq', 'action': 'not_found', 'status': 'skipped'})

    # 3. Stop RDS Aurora clusters first (before stopping member instances)
    logger.info("Stopping RDS Aurora clusters...")
    clusters = get_rds_clusters()
    for cluster in clusters:
        try:
            if cluster['status'] == 'available':
                rds.stop_db_cluster(DBClusterIdentifier=cluster['id'])
                results['rds_clusters'].append({'id': cluster['id'], 'action': 'stopped', 'status': 'success'})
                logger.info(f"Stopped RDS cluster: {cluster['id']}")
            else:
                results['rds_clusters'].append({'id': cluster['id'], 'action': f"already_{cluster['status']}", 'status': 'skipped'})
                logger.info(f"RDS cluster already in state {cluster['status']}: {cluster['id']}")
        except Exception as e:
            logger.error(f"Error stopping RDS cluster {cluster['id']}: {e}")
            results['errors'].append({'resource': cluster['id'], 'error': str(e)})

    # 4. Stop standalone RDS instances (not Aurora cluster members)
    logger.info("Stopping RDS instances...")
    instances = get_rds_instances()
    for instance in instances:
        # Skip Aurora cluster members - they're stopped with the cluster
        if instance['is_cluster_member']:
            logger.info(f"Skipping Aurora cluster member: {instance['id']}")
            continue

        try:
            if instance['status'] == 'available':
                rds.stop_db_instance(DBInstanceIdentifier=instance['id'])
                results['rds_instances'].append({'id': instance['id'], 'action': 'stopped', 'status': 'success'})
                logger.info(f"Stopped RDS instance: {instance['id']}")
            else:
                results['rds_instances'].append({'id': instance['id'], 'action': f"already_{instance['status']}", 'status': 'skipped'})
                logger.info(f"RDS instance already in state {instance['status']}: {instance['id']}")
        except Exception as e:
            logger.error(f"Error stopping RDS instance {instance['id']}: {e}")
            results['errors'].append({'resource': instance['id'], 'error': str(e)})

    return results


def start_services():
    """Start all services: RDS instances, RabbitMQ EC2, and ASGs"""
    results = {
        'asgs': [],
        'ec2': [],
        'rds_instances': [],
        'rds_clusters': [],
        'errors': []
    }

    # 1. Start RDS Aurora clusters first
    logger.info("Starting RDS Aurora clusters...")
    clusters = get_rds_clusters()
    for cluster in clusters:
        try:
            if cluster['status'] == 'stopped':
                rds.start_db_cluster(DBClusterIdentifier=cluster['id'])
                results['rds_clusters'].append({'id': cluster['id'], 'action': 'started', 'status': 'success'})
                logger.info(f"Started RDS cluster: {cluster['id']}")
            else:
                results['rds_clusters'].append({'id': cluster['id'], 'action': f"already_{cluster['status']}", 'status': 'skipped'})
                logger.info(f"RDS cluster already in state {cluster['status']}: {cluster['id']}")
        except Exception as e:
            logger.error(f"Error starting RDS cluster {cluster['id']}: {e}")
            results['errors'].append({'resource': cluster['id'], 'error': str(e)})

    # 2. Start standalone RDS instances
    logger.info("Starting RDS instances...")
    instances = get_rds_instances()
    for instance in instances:
        # Skip Aurora cluster members - they start with the cluster
        if instance['is_cluster_member']:
            logger.info(f"Skipping Aurora cluster member: {instance['id']}")
            continue

        try:
            if instance['status'] == 'stopped':
                rds.start_db_instance(DBInstanceIdentifier=instance['id'])
                results['rds_instances'].append({'id': instance['id'], 'action': 'started', 'status': 'success'})
                logger.info(f"Started RDS instance: {instance['id']}")
            else:
                results['rds_instances'].append({'id': instance['id'], 'action': f"already_{instance['status']}", 'status': 'skipped'})
                logger.info(f"RDS instance already in state {instance['status']}: {instance['id']}")
        except Exception as e:
            logger.error(f"Error starting RDS instance {instance['id']}: {e}")
            results['errors'].append({'resource': instance['id'], 'error': str(e)})

    # 3. Start RabbitMQ EC2 instance
    logger.info("Starting RabbitMQ EC2 instance...")
    rabbitmq_id = get_rabbitmq_instance_id()
    if rabbitmq_id:
        try:
            response = ec2.describe_instances(InstanceIds=[rabbitmq_id])
            state = response['Reservations'][0]['Instances'][0]['State']['Name']

            if state == 'stopped':
                ec2.start_instances(InstanceIds=[rabbitmq_id])
                results['ec2'].append({'id': rabbitmq_id, 'name': 'rabbitmq', 'action': 'started', 'status': 'success'})
                logger.info(f"Started RabbitMQ instance: {rabbitmq_id}")
            else:
                results['ec2'].append({'id': rabbitmq_id, 'name': 'rabbitmq', 'action': f'already_{state}', 'status': 'skipped'})
                logger.info(f"RabbitMQ instance already in state {state}: {rabbitmq_id}")
        except Exception as e:
            logger.error(f"Error starting RabbitMQ: {e}")
            results['errors'].append({'resource': 'rabbitmq', 'error': str(e)})
    else:
        logger.warning("RabbitMQ instance not found")
        results['ec2'].append({'name': 'rabbitmq', 'action': 'not_found', 'status': 'skipped'})

    # 4. Scale up ASGs to normal capacity
    logger.info("Scaling up ASGs...")
    for asg_name, config in ASG_CONFIGS.items():
        try:
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                MinSize=config['min'],
                MaxSize=config['max'],
                DesiredCapacity=config['desired']
            )
            results['asgs'].append({
                'name': asg_name,
                'action': f"scaled_to_{config['desired']}",
                'status': 'success'
            })
            logger.info(f"Scaled up ASG {asg_name}: min={config['min']}, max={config['max']}, desired={config['desired']}")
        except autoscaling.exceptions.ClientError as e:
            if 'AutoScalingGroupNotFound' in str(e):
                logger.warning(f"ASG not found: {asg_name}")
                results['asgs'].append({'name': asg_name, 'action': 'scale_up', 'status': 'not_found'})
            else:
                logger.error(f"Error scaling ASG {asg_name}: {e}")
                results['errors'].append({'resource': asg_name, 'error': str(e)})
        except Exception as e:
            logger.error(f"Error scaling ASG {asg_name}: {e}")
            results['errors'].append({'resource': asg_name, 'error': str(e)})

    return results


def lambda_handler(event, context):
    """
    Main Lambda handler
    Event should contain: {"action": "stop"} or {"action": "start"}
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Determine action from event
    action = event.get('action', '').lower()

    # Support EventBridge rule with detail
    if not action and 'detail' in event:
        action = event['detail'].get('action', '').lower()

    # Support direct invocation from EventBridge Scheduler
    if not action and 'resources' in event:
        # Check the rule name to determine action
        for resource in event.get('resources', []):
            if 'stop' in resource.lower():
                action = 'stop'
                break
            elif 'start' in resource.lower():
                action = 'start'
                break

    if action == 'stop':
        logger.info("Executing STOP operation...")
        results = stop_services()
        message = "Services stopped successfully"
    elif action == 'start':
        logger.info("Executing START operation...")
        results = start_services()
        message = "Services started successfully"
    else:
        error_msg = f"Invalid action: {action}. Must be 'stop' or 'start'"
        logger.error(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }

    # Check for errors
    if results.get('errors'):
        message = f"{message} with {len(results['errors'])} error(s)"
        status_code = 207  # Multi-Status
    else:
        status_code = 200

    response = {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'action': action,
            'environment': ENVIRONMENT,
            'results': results
        }, default=str)
    }

    logger.info(f"Response: {json.dumps(response, default=str)}")
    return response
