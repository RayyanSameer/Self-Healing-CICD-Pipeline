FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --upgrade "pip>=24.0" "setuptools>=78.1.1"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir --upgrade --force-reinstall "setuptools>=78.1.1" "msgpack>=1.2.1"
COPY . .

EXPOSE 5000

CMD ["python", "app.py"]