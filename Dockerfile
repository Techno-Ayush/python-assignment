# Base image: Python install hua milega
FROM python:3.9-slim

# Folder set kar rahe hain container ke andar
WORKDIR /app

# Requirements file copy kar rahe hain
COPY requirements.txt .

# Libraries install kar rahe hain
RUN pip install --no-cache-dir -r requirements.txt

# Baaki code copy kar rahe hain
COPY . .

# Port bata rahe hain
EXPOSE 5000

# App run karne ki command
CMD ["python", "app.py"]