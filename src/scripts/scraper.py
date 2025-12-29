import os
import requests
import pandas as pd
from dotenv import load_dotenv
from bs4 import BeautifulSoup
from urllib.parse import urljoin
from src.utils.db import SetupDatabase
import logging

load_dotenv()

URL = os.getenv("URL")

class ScraperDataB3():
    def __init__(self):
        self.url = os.getenv("URL")
        self.bucket_name = os.getenv("BUCKET_NAME")
        self.file_name = os.getenv("FILE_NAME")

    def get_data(self):
        try:
            response = requests.get(self.url, timeout=30)
            response.raise_for_status()
            return response.json
        except Exception as e
            

