# Tech Challenge - Fase 2: Pipeline Batch Bovespa

![Python](https://img.shields.io/badge/Python-3.9+-blue?style=for-the-badge&logo=python)
![Terraform](https://img.shields.io/badge/Terraform-1.0+-purple?style=for-the-badge&logo=terraform)
![AWS](https://img.shields.io/badge/AWS-Cloud-orange?style=for-the-badge&logo=amazon-aws)
![Apache Spark](https://img.shields.io/badge/Apache_Spark-Glue-red?style=for-the-badge&logo=apachespark)
![Status](https://img.shields.io/badge/Status-Concluído-brightgreen?style=for-the-badge)

> Pipeline de dados robusto e totalmente automatizado para extrair, processar e analisar dados do pregão da B3 utilizando arquitetura de Data Lake na AWS.

Este projeto consiste na implementação de uma arquitetura de Big Data Serverless na AWS para o processamento batch de dados financeiros. O objetivo principal é garantir que os dados brutos capturados via web scraping sejam transformados em informações valiosas, limpas e particionadas de forma eficiente para análise via SQL no Amazon Athena.

---

## 🏛️ Arquitetura e Pipeline

O projeto segue a arquitetura **Medallion (Raw e Refined)**, garantindo a linhagem e a qualidade do dado em cada etapa:



### Fluxo de Dados Passo a Passo:
1.  **Ingestão (Camada Raw):** Um script Python (`scraper.py`) realiza o scrap da API oficial da B3, trata os tipos numéricos e salva o arquivo no S3 em formato Parquet com partição diária (`year/month/day`).
2.  **Gatilho (Trigger):** O upload do arquivo para a pasta `raw/` dispara uma **AWS Lambda** via S3 Event Notifications.
3.  **Orquestração:** A função Lambda, agindo de forma serverless, inicia o Job de ETL no **AWS Glue**.
4.  **Processamento ETL:** O Job do Glue executa um script PySpark que realiza transformações de negócio, como agrupamentos, renomeação de colunas e cálculos de datas.
5.  **Armazenamento (Camada Refined):** Os dados processados são salvos em formato Parquet na pasta `refined`, particionados por data e pelo ticker da ação para otimização de custos e performance.
6.  **Catálogo e Consulta:** O Glue Job cataloga automaticamente os metadados no **Glue Catalog**, disponibilizando os dados para consultas SQL imediatas no **Amazon Athena**.

---

## 🛠️ Tecnologias e Ferramentas AWS

O projeto foi construído utilizando ferramentas de ponta para garantir escalabilidade e baixo custo operacional:

| Ferramenta | Descrição |
| :--- | :--- |
| **Python / PySpark** | Linguagem utilizada para extração (Scraping), orquestração (Lambda) e processamento (Glue). |
| **Terraform** | Utilizado para o provisionamento de toda a infraestrutura como código (IaC), garantindo reprodutibilidade. |
| **AWS S3** | Data Lake responsável pelo armazenamento das camadas Raw e Refined. |
| **AWS Lambda** | Serviço serverless para orquestração do pipeline baseada em eventos. |
| **AWS Glue** | Motor de processamento Spark para transformações batch complexas. |
| **Amazon Athena** | Interface de consulta SQL interativa sobre os dados do S3. |

---

## ⚙️ Lógica de Negócio e Transformações (Requisito 5)

Dentro do **AWS Glue Job**, as seguintes transformações são aplicadas para atender aos requisitos do projeto:

* **A: Agrupamento e Soma:** Utilização de `Window Functions` para calcular a soma da participação por ticker.
* **B: Padronização:** Renomeação de colunas técnicas para nomes amigáveis (ex: `cod` para `ticker`).
* **C: Inteligência de Datas:** Cálculo de diferença de dias entre a data do pregão e a data atual para análise de defasagem.

---

## 📦 Como Instalar e Rodar

### Pré-requisitos
* **AWS CLI** configurada com credenciais administrativas.
* **Terraform** e **Python 3.9+** instalados.

### 1. Provisionamento
```bash
cd src/terraform
terraform init
terraform apply -auto-approve