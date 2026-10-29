FROM node:22-slim
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev --no-audit --no-fund
COPY . .
ENV OTEL_SERVICE_NAME=storefront \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
CMD ["npm", "start"]
