FROM python:3.12-slim
RUN useradd --system --no-create-home app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
USER app
EXPOSE 8001
CMD ["gunicorn", "--bind", "0.0.0.0:8001", "--access-logfile", "-", "app:app"]
