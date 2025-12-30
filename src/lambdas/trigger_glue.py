import boto3
import os
import json
import logging

# Configuração de Logs para monitoramento no CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Função acionada pelo S3 para iniciar o Job do Glue (Requisito 4).
    """
    # 1. Recupera o nome do Job do Glue definido no Terraform
    glue_job_name = os.environ.get('GLUE_JOB_NAME')
    glue_client = boto3.client('glue')

    try:
        # Registra no log qual arquivo disparou o gatilho (opcional, para auditoria)
        if 'Records' in event:
            file_name = event['Records'][0]['s3']['object']['key']
            logger.info(f"Arquivo detectado: {file_name}")

        # 2. Inicia o Job do Glue (Ação obrigatória do Requisito 16)
        logger.info(f"Iniciando Glue Job: {glue_job_name}")
        response = glue_client.start_job_run(JobName=glue_job_name)
        
        job_run_id = response['JobRunId']
        logger.info(f"Job iniciado com sucesso. RunId: {job_run_id}")

        return {
            'statusCode': 200,
            'body': json.dumps(f"Glue Job {glue_job_name} disparado. RunId: {job_run_id}")
        }

    except Exception as e:
        logger.error(f"Erro ao iniciar o Glue Job: {str(e)}")
        raise e