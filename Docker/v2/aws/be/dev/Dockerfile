FROM amazoncorretto:21
WORKDIR /app
COPY dojangkok-server-jar.jar dojangkok-server-jar.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "dojangkok-server-jar.jar", "--spring.config.location=file:/app/config/application.yaml"]