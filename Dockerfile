# Use a minimal base image for a leaner build
FROM ruby:3.2.2-slim-bullseye AS base

# Set build arguments for user and group IDs
ARG POSTAL_UID=999
ARG POSTAL_GID=999

# Create a dedicated non-root user for running Postal
RUN groupadd -g $POSTAL_GID postal && \
    useradd -r -u $POSTAL_UID -g postal -m -s /bin/bash postal

# Set the shell to bash with strict error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install required packages in one step and clean up to reduce image size
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    dirmngr \
    apt-transport-https \
    curl \
    netcat \
    build-essential \
    libmariadb-dev \
    libcap2-bin \
    nano \
    nodejs \
  && rm -rf /var/lib/apt/lists/*

# Allow Ruby to bind to privileged ports (needed for SMTP)
RUN setcap 'cap_net_bind_service=+ep' /usr/local/bin/ruby

# Set the working directory
WORKDIR /opt/postal

# Copy all application files into the container
COPY --chown=postal . .

# Switch to the non-root postal user
USER postal

# Install bundler without documentation to save space
RUN gem install bundler -v 2.5.6 --no-document

# Copy the Gemfile and Gemfile.lock and install Ruby dependencies in parallel
COPY --chown=postal Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Precompile Rails assets to reduce startup time
RUN bundle exec rake assets:precompile

# Set the environment variable for Postal's configuration file path
ENV POSTAL_CONFIG_FILE_PATH=/config/postal.yml

# Expose required ports for SMTP, HTTP, HTTPS, etc.
EXPOSE 25 80 443 587 2525 465

# Add a health check to monitor container status
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5000 || exit 1

# Start the Postal application
CMD ["postal"]
