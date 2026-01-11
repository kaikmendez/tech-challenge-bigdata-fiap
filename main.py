import subprocess
import boto3
import sys
import os
from src.scripts.scraper import B3Ingestion

# Nome do bucket definido no seu main.tf
BUCKET_NAME = "tech-challenge-fiap-bovespa-datalake"

def check_infrastructure():
    """Verifica se o bucket do S3 existe."""
    s3 = boto3.client('s3')
    try:
        s3.head_bucket(Bucket=BUCKET_NAME)
        print(f"✅ Infraestrutura validada: Bucket {BUCKET_NAME} está online.")
        return True
    except:
        print(f"⚠️ Bucket {BUCKET_NAME} não encontrado.")
        return False

def deploy_infrastructure():
    """Executa o Terraform para criar o ambiente automaticamente."""
    print("🚀 Iniciando criação da infraestrutura via Terraform...")
    
    # Define o caminho para a pasta do terraform (ajuste se necessário)
    tf_path = os.path.join(os.getcwd(), "src/terraform")
    
    try:
        # 1. Terraform Init
        print("📦 Rodando terraform init...")
        subprocess.run(["terraform", "init"], cwd=tf_path, check=True)
        
        # 2. Terraform Apply
        # O -auto-approve é vital aqui para não travar o script pedindo 'yes'
        print("🏗️ Rodando terraform apply...")
        subprocess.run(["terraform", "apply", "-auto-approve"], cwd=tf_path, check=True)
        
        print("✨ Infraestrutura criada com sucesso!")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Erro ao executar Terraform: {e}")
        return False

def run_pipeline():
    try:
        # Tenta validar. Se não existir, tenta criar.
        if not check_infrastructure():
            if not deploy_infrastructure():
                print("🛑 Falha crítica: Não foi possível subir a infraestrutura.")
                sys.exit(1)

        # Agora que a infra existe, inicia a extração da B3
        ingestor = B3Ingestion(bucket_name=BUCKET_NAME)
        data = ingestor.fetch_data()
        df = ingestor.process_data(data)
        ingestor.upload_to_s3(df)
        
        print("🎯 Pipeline finalizado! Os dados estão no S3 e o Glue foi acionado.")
        
    except Exception as e:
        print(f"💥 Erro inesperado: {e}")

if __name__ == "__main__":
    run_pipeline()