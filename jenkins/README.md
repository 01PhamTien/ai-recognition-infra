# Jenkins with Docker access

This stack upgrades the existing Jenkins container for the AI Recognition DevOps project.
It preserves the existing Docker volume jenkins_home; it does not create a replacement
volume or delete Jenkins jobs, plugins, users, or build history.

## What it provides

- Jenkins LTS on JDK 21.
- Docker CLI, connected to Docker Desktop through /var/run/docker.sock.
- Python 3 + venv for backend tests.
- Node.js 22 + npm for frontend tests/builds.
- Existing Jenkins data volume mounted as an external volume.

## Important security note

Access to /var/run/docker.sock grants Jenkins effective administrative control over
the Docker Engine and can be equivalent to host-level root access. Use this only for
the trusted Jenkins instance in this coursework environment. Do not expose the socket
to application containers or untrusted build jobs.

## Upgrade an existing Windows Docker Desktop Jenkins container

Run these commands from the repository root in PowerShell.

1. Confirm the existing volume exists:

   ```powershell
   docker volume inspect jenkins_home
   ```

2. Stop and remove only the old Jenkins container. This does not remove its named volume:

   ```powershell
   docker stop jenkins
   docker rm jenkins
   ```

   Do not run docker rm -v, docker volume rm, or docker compose down -v.

3. Build and start the extended Jenkins image:

   ```powershell
   docker compose -f .\jenkins\compose.yaml up -d --build
   ```

4. Verify Docker access and the CI runtimes:

   ```powershell
   docker exec jenkins docker version
   docker exec jenkins docker ps
   docker exec jenkins python3 --version
   docker exec jenkins node --version
   docker exec jenkins npm --version
   ```

5. If Docker reports a socket permission error, inspect the socket group ID:

   ```powershell
   docker exec jenkins sh -c "stat -c '%g %a %U:%G' /var/run/docker.sock"
   ```

   Set the reported numeric group ID as DOCKER_GID in a .env file beside
   jenkins/compose.yaml (for example, DOCKER_GID=998), then recreate the
   container with docker compose -f .\jenkins\compose.yaml up -d --force-recreate.
   The default is group ID 0 and may already work on Docker Desktop.

## Rollback

The original image can be restored while keeping all Jenkins data:

```powershell
docker stop jenkins
docker rm jenkins
docker run -d --name jenkins --restart unless-stopped -p 8080:8080 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts-jdk21
```

Do not delete the jenkins_home volume.
