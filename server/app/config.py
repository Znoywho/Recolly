import os

from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.environ["POSTGRES_DATABASE_URL"]

class Config:
    POSTGRES_DATABASE_URI = DATABASE_URL

