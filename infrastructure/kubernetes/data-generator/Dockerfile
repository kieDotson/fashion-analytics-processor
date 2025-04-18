# Use official Python image as base
FROM python:3.11-slim

# Set working directory inside the container
WORKDIR /app

# Copy the application files
COPY . .

# Install dependencies
RUN pip install --no-cache-dir fastapi uvicorn faker pydantic

# Expose the FastAPI default port
EXPOSE 5000

# Run the application with Uvicorn, specifying generator.py
CMD ["uvicorn", "data-generator:app", "--host", "0.0.0.0", "--port", "5000"]
