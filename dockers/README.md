# Cloud Tools Docker Setup

This repository contains the configuration for a Docker image designed to run on-premise environments. The image includes various cloud-related tools and utilities.

## Running the Docker Image On-Premise

### Step 1: Build the Docker Image

To create the Docker image locally, use the following command:

```bash
docker build -t cloud-tools .
```

### Step 2: Run the Docker Container

After building the image, you can run the container interactively using:

```bash
docker run -it cloud-tools
```

### Additional Information

- This image is also **published on Docker Hub** for easier access and distribution.
- All updates to the image are **automatically synced** to Docker Hub via **GitHub Actions**. The workflow for this automation is located in:

  ```bash
  .github/workflows/docker-build.yml
  ```

