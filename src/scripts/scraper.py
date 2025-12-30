import os
import boto3
import pandas as pd
import requests
import logging
from io import BytesIO
from datetime import datetime   

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class B3Ingestion:
    def __init__(self, bucket_name: str, index_name: str = 'IBOV'):
        self.bucket_name = bucket_name
        self.index_name = index_name.upper()
        # Endpoint simplificado descoberto via inspeção de rede
        self.base_url = f"https://sistemaswebb3-listados.b3.com.br/indexProxy/indexCall/GetPortfolioDay/{self.index_name}"
        self.s3_client = boto3.client('s3')

    def fetch_data(self) -> dict:
        logger.info(f"Extraindo dados da B3 para o índice: {self.index_name}")
        try:
            response = requests.get(self.base_url, timeout=30)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Erro na requisição: {e}")
            raise

    def process_data(self, raw_json: dict) -> pd.DataFrame:
        results = raw_json.get('results', [])
        if not results:
            raise ValueError("API retornou lista vazia.")

        df = pd.DataFrame(results)
        
        # Tratamento de tipos (Requisito 2)
        cols_numericas = ['theoricalQty', 'part']
        for col in cols_numericas:
            if col in df.columns:
                df[col] = df[col].astype(str).str.replace('.', '', regex=False).str.replace(',', '.', regex=False)
                df[col] = pd.to_numeric(df[col], errors='coerce')

        # Adiciona data de referência para partição
        data_str = raw_json.get('header', {}).get('date', datetime.now().strftime("%d/%m/%y"))
        df['data_pregao'] = datetime.strptime(data_str, "%d/%m/%y").date()
        return df

    def upload_to_s3(self, df: pd.DataFrame):
        ref_date = df['data_pregao'].iloc[0]
        # Estrutura de partição diária (Requisito 14)
        partition_path = f"year={ref_date.year}/month={ref_date.month:02d}/day={ref_date.day:02d}"
        s3_key = f"raw/{partition_path}/b3_data.parquet"

        out_buffer = BytesIO()
        df.to_parquet(out_buffer, index=False, engine='pyarrow')
        
        self.s3_client.put_object(
            Bucket=self.bucket_name,
            Key=s3_key,
            Body=out_buffer.getvalue()
        )
        logger.info(f"Upload realizado: s3://{self.bucket_name}/{s3_key}")