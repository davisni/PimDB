# The image for the PIM screens: Python plus the packages in requirements.txt.
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# --reload restarts the app when a file changes, so edits show up without a rebuild.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
