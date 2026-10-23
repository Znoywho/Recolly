# Base Image
FROM python:3.12-slim
# mainly working
WORKDIR app/
COPY requirements.txt .
# Execute the new layer on top of the current image
RUN pip install --no-cache-dir -r requirements.txt
# Copy the the current app to container
COPY . .
EXPOSE 8765
# Only once and the last in dockerfile
CMD ["python", "-m", "app.main"]
