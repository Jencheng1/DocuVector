from typing import Dict, List, Any, Optional
import mlflow
import dvc.api
from mlflow.tracking import MlflowClient
import boto3
import logging
from datetime import datetime
import os
import json

class ModelManager:
    def __init__(self, tracking_uri: str, s3_bucket: str):
        self.logger = logging.getLogger(__name__)
        mlflow.set_tracking_uri(tracking_uri)
        self.client = MlflowClient()
        self.s3 = boto3.client('s3')
        self.s3_bucket = s3_bucket
        
    def log_experiment(self, experiment_name: str, 
                      params: Dict[str, Any],
                      metrics: Dict[str, float],
                      artifacts: List[str]):
        """Log experiment details to MLflow"""
        try:
            with mlflow.start_run(experiment_name=experiment_name):
                # Log parameters
                mlflow.log_params(params)
                
                # Log metrics
                mlflow.log_metrics(metrics)
                
                # Log artifacts
                for artifact in artifacts:
                    mlflow.log_artifact(artifact)
                    
                # Log model
                mlflow.pyfunc.log_model(
                    "model",
                    python_model=self._create_pyfunc_model(),
                    registered_model_name=experiment_name
                )
        except Exception as e:
            self.logger.error(f"Error logging experiment: {e}")
            raise
            
    def register_model(self, run_id: str, model_name: str,
                      stage: str = "Production"):
        """Register a model version"""
        try:
            model_uri = f"runs:/{run_id}/model"
            result = mlflow.register_model(
                model_uri=model_uri,
                name=model_name
            )
            
            # Transition model to specified stage
            self.client.transition_model_version_stage(
                name=model_name,
                version=result.version,
                stage=stage
            )
            
            return result
        except Exception as e:
            self.logger.error(f"Error registering model: {e}")
            raise
            
    def version_data(self, data_path: str, message: str):
        """Version data using DVC"""
        try:
            # Add data to DVC
            dvc.api.add(data_path)
            
            # Commit changes
            os.system(f"dvc commit -m '{message}'")
            
            # Push to remote storage
            os.system("dvc push")
            
            return {
                "data_path": data_path,
                "message": message,
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            self.logger.error(f"Error versioning data: {e}")
            raise
            
    def manage_model_lifecycle(self, model_name: str,
                             action: str,
                             version: Optional[str] = None):
        """Manage model lifecycle stages"""
        try:
            if action == "archive":
                self.client.transition_model_version_stage(
                    name=model_name,
                    version=version,
                    stage="Archived"
                )
            elif action == "promote":
                self.client.transition_model_version_stage(
                    name=model_name,
                    version=version,
                    stage="Production"
                )
            elif action == "deprecate":
                self.client.transition_model_version_stage(
                    name=model_name,
                    version=version,
                    stage="Deprecated"
                )
                
            return {
                "model_name": model_name,
                "version": version,
                "action": action,
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            self.logger.error(f"Error managing model lifecycle: {e}")
            raise
            
    def track_model_performance(self, model_name: str,
                              version: str,
                              metrics: Dict[str, float]):
        """Track model performance metrics"""
        try:
            # Log metrics to MLflow
            with mlflow.start_run(nested=True):
                mlflow.log_metrics(metrics)
                
            # Store metrics in S3 for long-term tracking
            self.s3.put_object(
                Bucket=self.s3_bucket,
                Key=f"model_metrics/{model_name}/{version}/{datetime.now().isoformat()}.json",
                Body=json.dumps(metrics)
            )
            
            return metrics
        except Exception as e:
            self.logger.error(f"Error tracking model performance: {e}")
            raise
            
    def _create_pyfunc_model(self):
        """Create a PyFunc model for MLflow"""
        class ModelWrapper(mlflow.pyfunc.PythonModel):
            def __init__(self):
                self.model = None
                
            def load_context(self, context):
                # Load model from context
                pass
                
            def predict(self, context, model_input):
                # Make predictions
                return model_input
                
        return ModelWrapper()
        
    def compare_models(self, model_name: str,
                      versions: List[str]) -> Dict[str, Any]:
        """Compare performance of different model versions"""
        try:
            comparison = {}
            
            for version in versions:
                # Get metrics from MLflow
                run = self.client.get_run(version)
                metrics = run.data.metrics
                
                # Get metrics from S3
                response = self.s3.list_objects_v2(
                    Bucket=self.s3_bucket,
                    Prefix=f"model_metrics/{model_name}/{version}/"
                )
                
                s3_metrics = []
                for obj in response.get('Contents', []):
                    data = self.s3.get_object(
                        Bucket=self.s3_bucket,
                        Key=obj['Key']
                    )
                    s3_metrics.append(json.loads(data['Body'].read()))
                    
                comparison[version] = {
                    "mlflow_metrics": metrics,
                    "historical_metrics": s3_metrics
                }
                
            return comparison
        except Exception as e:
            self.logger.error(f"Error comparing models: {e}")
            raise 