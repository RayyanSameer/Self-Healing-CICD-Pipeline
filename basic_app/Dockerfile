FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir --upgrade "pip>=24.0" "setuptools>=78.1.1"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]