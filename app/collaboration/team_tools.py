from typing import Dict, List, Optional
import boto3
import json
from datetime import datetime
import logging
from dataclasses import dataclass
from enum import Enum

class TeamRole(Enum):
    DATA_SCIENTIST = "data_scientist"
    ML_ENGINEER = "ml_engineer"
    DEVOPS = "devops"
    PRODUCT_MANAGER = "product_manager"
    SECURITY = "security"

@dataclass
class TeamMember:
    name: str
    role: TeamRole
    email: str
    permissions: List[str]

class TeamCollaboration:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.sns = boto3.client('sns')
        self.sqs = boto3.client('sqs')
        self.chime = boto3.client('chime')
        self.codecommit = boto3.client('codecommit')
        
    def create_team_channel(self, channel_name: str, team_members: List[TeamMember]):
        """Create a team collaboration channel"""
        try:
            response = self.chime.create_channel(
                Name=channel_name,
                Mode='RESTRICTED',
                Privacy='PRIVATE'
            )
            
            # Add team members to the channel
            for member in team_members:
                self.chime.create_channel_membership(
                    ChannelArn=response['ChannelArn'],
                    MemberArn=f"arn:aws:chime:us-east-1:{self.get_account_id()}:user/{member.email}"
                )
                
            return response['ChannelArn']
        except Exception as e:
            self.logger.error(f"Error creating team channel: {e}")
            raise
            
    def setup_notification_topic(self, topic_name: str, team_members: List[TeamMember]):
        """Setup SNS topic for team notifications"""
        try:
            response = self.sns.create_topic(Name=topic_name)
            
            # Subscribe team members
            for member in team_members:
                self.sns.subscribe(
                    TopicArn=response['TopicArn'],
                    Protocol='email',
                    Endpoint=member.email
                )
                
            return response['TopicArn']
        except Exception as e:
            self.logger.error(f"Error setting up notification topic: {e}")
            raise
            
    def create_team_queue(self, queue_name: str):
        """Create SQS queue for team task management"""
        try:
            response = self.sqs.create_queue(
                QueueName=queue_name,
                Attributes={
                    'VisibilityTimeout': '300',
                    'MessageRetentionPeriod': '86400'
                }
            )
            return response['QueueUrl']
        except Exception as e:
            self.logger.error(f"Error creating team queue: {e}")
            raise
            
    def setup_code_review_workflow(self, repository_name: str):
        """Setup code review workflow in CodeCommit"""
        try:
            # Create approval rule template
            response = self.codecommit.create_approval_rule_template(
                approvalRuleTemplateName=f"{repository_name}-review",
                approvalRuleTemplateContent=json.dumps({
                    "Version": "2018-11-08",
                    "Statements": [
                        {
                            "Type": "Approvers",
                            "NumberOfApprovalsNeeded": 2
                        }
                    ]
                })
            )
            
            # Associate template with repository
            self.codecommit.associate_approval_rule_template_with_repository(
                approvalRuleTemplateName=response['approvalRuleTemplate']['approvalRuleTemplateName'],
                repositoryName=repository_name
            )
            
            return response['approvalRuleTemplate']['approvalRuleTemplateName']
        except Exception as e:
            self.logger.error(f"Error setting up code review workflow: {e}")
            raise
            
    def create_team_dashboard(self, dashboard_name: str, metrics: List[str]):
        """Create CloudWatch dashboard for team metrics"""
        try:
            dashboard_body = {
                "widgets": [
                    {
                        "type": "metric",
                        "x": 0,
                        "y": 0,
                        "width": 12,
                        "height": 6,
                        "properties": {
                            "metrics": [[metric] for metric in metrics],
                            "view": "timeSeries",
                            "stacked": False,
                            "region": "us-east-1",
                            "title": f"{dashboard_name} Metrics"
                        }
                    }
                ]
            }
            
            response = boto3.client('cloudwatch').put_dashboard(
                DashboardName=dashboard_name,
                DashboardBody=json.dumps(dashboard_body)
            )
            
            return response['DashboardValidationMessages']
        except Exception as e:
            self.logger.error(f"Error creating team dashboard: {e}")
            raise
            
    def setup_incident_response(self, team_members: List[TeamMember]):
        """Setup incident response workflow"""
        try:
            # Create incident response topic
            topic_arn = self.setup_notification_topic(
                "docuvector-incident-response",
                team_members
            )
            
            # Create incident queue
            queue_url = self.create_team_queue("incident-response")
            
            return {
                "topic_arn": topic_arn,
                "queue_url": queue_url
            }
        except Exception as e:
            self.logger.error(f"Error setting up incident response: {e}")
            raise
            
    def get_account_id(self) -> str:
        """Get AWS account ID"""
        sts = boto3.client('sts')
        return sts.get_caller_identity()['Account']
        
    def log_team_activity(self, activity: str, member: TeamMember):
        """Log team activity for auditing"""
        self.logger.info(
            f"Team activity: {activity}",
            extra={
                "member": member.name,
                "role": member.role.value,
                "timestamp": datetime.now().isoformat()
            }
        ) 