# ---- build ----
FROM openjdk:8-jdk-slim AS build
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /work
COPY . .
RUN chmod +x mvnw && ./mvnw -B -DskipTests clean package


# ---- run (alpine runner) ----
FROM eclipse-temurin:8-jdk-alpine
WORKDIR /app
COPY --from=build /work/target/*-SNAPSHOT.jar /app/app.jar
# optional: ensure tzdata if you rely on named time zones
# RUN apk add --no-cache tzdata
ENV JAVA_OPTS=""
EXPOSE 9191
RUN adduser -S -u 10001 appuser && chown -R appuser /app
USER 10001
ENTRYPOINT ["java","-jar","/app/app.jar"]
