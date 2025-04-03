from typing import Dict, List, Any, Optional
import boto3
import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest
from prophet import Prophet
import logging
from datetime import datetime, timedelta

class PredictiveAnalytics:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.cloudwatch = boto3.client('cloudwatch')
        self.sagemaker = boto3.client('sagemaker')
        
    def detect_anomalies(self, metric_data: pd.DataFrame) -> Dict[str, Any]:
        """Detect anomalies in metric data using Isolation Forest"""
        try:
            model = IsolationForest(contamination=0.1)
            predictions = model.fit_predict(metric_data)
            anomalies = metric_data[predictions == -1]
            
            return {
                "anomalies": anomalies.to_dict(),
                "confidence": model.score_samples(metric_data).tolist()
            }
        except Exception as e:
            self.logger.error(f"Error in anomaly detection: {e}")
            raise
            
    def forecast_metrics(self, metric_data: pd.DataFrame, 
                        forecast_period: int = 24) -> Dict[str, Any]:
        """Forecast future metric values using Prophet"""
        try:
            df = metric_data.reset_index()
            df.columns = ['ds', 'y']
            
            model = Prophet()
            model.fit(df)
            
            future = model.make_future_dataframe(periods=forecast_period, freq='H')
            forecast = model.predict(future)
            
            return {
                "forecast": forecast[['ds', 'yhat', 'yhat_lower', 'yhat_upper']].to_dict(),
                "trend": model.params['trend'].tolist()
            }
        except Exception as e:
            self.logger.error(f"Error in metric forecasting: {e}")
            raise
            
    def optimize_performance(self, current_metrics: Dict[str, float],
                           target_metrics: Dict[str, float]) -> Dict[str, Any]:
        """Generate performance optimization recommendations"""
        recommendations = []
        
        # CPU optimization
        if current_metrics['CPUUtilization'] > target_metrics['CPUUtilization']:
            recommendations.append({
                "type": "CPU",
                "action": "Scale out",
                "reason": "High CPU utilization",
                "priority": "High"
            })
            
        # Memory optimization
        if current_metrics['MemoryUtilization'] > target_metrics['MemoryUtilization']:
            recommendations.append({
                "type": "Memory",
                "action": "Increase memory allocation",
                "reason": "High memory utilization",
                "priority": "High"
            })
            
        # Latency optimization
        if current_metrics['Latency'] > target_metrics['Latency']:
            recommendations.append({
                "type": "Latency",
                "action": "Optimize query patterns",
                "reason": "High latency",
                "priority": "Medium"
            })
            
        return {
            "recommendations": recommendations,
            "current_metrics": current_metrics,
            "target_metrics": target_metrics
        }
        
    def automated_remediation(self, anomaly: Dict[str, Any]) -> Dict[str, Any]:
        """Execute automated remediation based on anomaly type"""
        try:
            remediation_actions = {
                "high_cpu": self._remediate_high_cpu,
                "high_memory": self._remediate_high_memory,
                "high_latency": self._remediate_high_latency
            }
            
            action = remediation_actions.get(anomaly['type'], self._default_remediation)
            return action(anomaly)
        except Exception as e:
            self.logger.error(f"Error in automated remediation: {e}")
            raise
            
    def _remediate_high_cpu(self, anomaly: Dict[str, Any]) -> Dict[str, Any]:
        """Remediate high CPU utilization"""
        try:
            # Scale out ECS service
            ecs = boto3.client('ecs')
            response = ecs.update_service(
                cluster=anomaly['cluster'],
                service=anomaly['service'],
                desiredCount=anomaly['current_count'] + 1
            )
            
            return {
                "action": "scaled_out",
                "service": anomaly['service'],
                "new_count": anomaly['current_count'] + 1
            }
        except Exception as e:
            self.logger.error(f"Error in CPU remediation: {e}")
            raise
            
    def _remediate_high_memory(self, anomaly: Dict[str, Any]) -> Dict[str, Any]:
        """Remediate high memory utilization"""
        try:
            # Update ECS task definition with higher memory
            ecs = boto3.client('ecs')
            response = ecs.register_task_definition(
                family=anomaly['task_family'],
                memory=str(int(anomaly['current_memory']) * 1.5)
            )
            
            return {
                "action": "increased_memory",
                "task_family": anomaly['task_family'],
                "new_memory": int(anomaly['current_memory']) * 1.5
            }
        except Exception as e:
            self.logger.error(f"Error in memory remediation: {e}")
            raise
            
    def _remediate_high_latency(self, anomaly: Dict[str, Any]) -> Dict[str, Any]:
        """Remediate high latency"""
        try:
            # Update WAF rules to block suspicious traffic
            waf = boto3.client('wafv2')
            response = waf.update_web_acl(
                Name=anomaly['web_acl'],
                Scope='REGIONAL',
                DefaultAction={'Allow': {}},
                Rules=[
                    {
                        'Name': 'RateLimitRule',
                        'Priority': 1,
                        'Statement': {
                            'RateBasedStatement': {
                                'Limit': 1000,
                                'AggregateKeyType': 'IP'
                            }
                        },
                        'Action': {'Block': {}},
                        'VisibilityConfig': {
                            'SampledRequestsEnabled': True,
                            'CloudWatchMetricsEnabled': True,
                            'MetricName': 'RateLimitRule'
                        }
                    }
                ]
            )
            
            return {
                "action": "updated_waf",
                "web_acl": anomaly['web_acl'],
                "new_rule": "RateLimitRule"
            }
        except Exception as e:
            self.logger.error(f"Error in latency remediation: {e}")
            raise
            
    def _default_remediation(self, anomaly: Dict[str, Any]) -> Dict[str, Any]:
        """Default remediation action"""
        return {
            "action": "notified_team",
            "anomaly": anomaly,
            "timestamp": datetime.now().isoformat()
        } 