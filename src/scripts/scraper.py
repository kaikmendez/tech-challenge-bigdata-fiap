import os
import base64
import json
import logging
import requests
import pandas as pd
import boto3
from io import BytesIO
from datetime import datetime

# Configuração do logger para este módulo
logger = logging.getLogger(__name__)

class B3Ingestion:
    def __init__(self, bucket_name: str, index_name: str = 'IBOV'):
        self.bucket_name = bucket_name
        self.index_name = index_name.upper()
        
        # Codificação necessária para a API da B3
        params = {"index": self.index_name, "language": "pt-br"}
        params_encoded = base64.b64encode(json.dumps(params).encode()).decode()
        
        self.base_url = f"https://sistemaswebb3-listados.b3.com.br/indexProxy/indexCall/GetPortfolioDay/{params_encoded}"
        self.s3_client = boto3.client('s3')

    def fetch_data(self) -> dict:
        logger.info(f"Extraindo dados da B3 para o índice: {self.index_name}")
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Referer': 'https://www.b3.com.br/'
        }
        try:
            response = requests.get(self.base_url, headers=headers, timeout=30)
            if response.status_code != 200:
                logger.error(f"Erro B3: Status {response.status_code} - {response.text[:100]}")
                raise Exception("Falha ao acessar API da B3")
            return response.json()
        except Exception as e:
            logger.error(f"Erro na requisição: {e}")
            raise

    def process_data(self, raw_json: dict) -> pd.DataFrame:
        """Transforma o JSON bruto em um DataFrame tratado."""
        results = raw_json.get('results', [])
        if not results:
            raise ValueError("API retornou lista vazia ou formato inválido.")

        df = pd.DataFrame(results)
        
        # Tratamento de tipos numéricos
        cols_numericas = ['theoricalQty', 'part']
        for col in cols_numericas:
            if col in df.columns:
                df[col] = df[col].astype(str).str.replace('.', '', regex=False).str.replace(',', '.', regex=False)
                df[col] = pd.to_numeric(df[col], errors='coerce')

        # Adiciona data de referência
        header_date = raw_json.get('header', {}).get('date')
        if header_date:
            try:
                df['data_pregao'] = datetime.strptime(header_date, "%d/%m/%y").date()
            except:
                df['data_pregao'] = datetime.now().date()
        else:
            df['data_pregao'] = datetime.now().date()
            
        return df

    def upload_to_s3(self, df: pd.DataFrame):
        """Salva o DataFrame no S3 em formato Parquet."""
        ref_date = df['data_pregao'].iloc[0]
        partition_path = f"year={ref_date.year}/month={ref_date.month:02d}/day={ref_date.day:02d}"
        s3_key = f"raw/{partition_path}/b3_data.parquet"

        out_buffer = BytesIO()
        df.to_parquet(out_buffer, index=False, engine='pyarrow')
        
        self.s3_client.put_object(
            Bucket=self.bucket_name,
            Key=s3_key,
            Body=out_buffer.getvalue()
        )
        logger.info(f"✅ Upload realizado com sucesso: s3://{self.bucket_name}/{s3_key}")