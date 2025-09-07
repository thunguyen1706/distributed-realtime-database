FROM fluentd:v1.16-1

USER root

# Install plugins
RUN gem install fluent-plugin-elasticsearch

# Copy configuration
COPY fluent.conf /fluentd/etc/fluent.conf

USER fluent