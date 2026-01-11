import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

# 1. Configurações Iniciais
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

DATABASE_NAME = args['DATABASE_NAME']
BUCKET = "tech-challenge-fiap-bovespa-datalake"
SOURCE_PATH = f"s3://{BUCKET}/raw/"
TARGET_PATH = f"s3://{BUCKET}/refined/"

# 2. Leitura dos dados brutos (Requisito 2)
df_raw = spark.read.parquet(SOURCE_PATH)

# --- REQUISITO 5-B: Renomear colunas existentes ---
df = df_raw.withColumnRenamed("cod", "ticker") \
           .withColumnRenamed("theoricalQty", "quantidade_teorica")

# --- REQUISITO 5-C: Realizar um cálculo com campos de data ---
df = df.withColumn("dias_desde_pregao", F.datediff(F.current_date(), F.col("data_pregao"))) \
       .withColumn("dia_da_semana", F.date_format(F.col("data_pregao"), "EEEE"))

# --- REQUISITO 5-A: Agrupamento numérico, sumarização ou soma ---
window_spec = Window.partitionBy("ticker")
df = df.withColumn("soma_participacao_ticker", F.sum("part").over(window_spec))

# --- REQUISITO 6: Preparação para Particionamento ---
df = df.withColumn("ano", F.year("data_pregao")) \
       .withColumn("mes", F.month("data_pregao")) \
       .withColumn("dia", F.dayofmonth("data_pregao"))

# 3. Conversão para DynamicFrame para Catalogação Automática
dynamic_frame = DynamicFrame.fromDF(df, glueContext, "df_final")

# 4. Escrita e Catalogação Automática (Sintaxe definitiva para Glue 4.0)
# Todos os parâmetros de catálogo devem estar dentro de connection_options
print(f"Salvando dados refinados e catalogando no banco: {DATABASE_NAME}")

glueContext.write_dynamic_frame.from_options(
    frame=dynamic_frame,
    connection_type="s3",
    connection_options={
        "path": TARGET_PATH,
        "partitionKeys": ["ano", "mes", "dia", "ticker"], # Requisito 6 
        "enableUpdateCatalog": True,                      # Requisito 7 
        "updateBehavior": "UPDATE_IN_DATABASE",            # Requisito 23 
        "catalogDatabase": DATABASE_NAME,
        "catalogTableName": "bovespa_final"
    },
    format="parquet",
    format_options={
        "useGlueParquetWriter": True
    },
    transformation_ctx="datasink"
)

job.commit()
print("🎯 Sucesso! Pipeline concluído e dados catalogados sem erros de tipo.")