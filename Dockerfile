# Multi-stage Dockerfile for Church Digital Platform API
# Optimized for security (non-root container) and minimal attack surface (.NET 10)

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy project files for layer caching
COPY ["backend/Church.API/Church.API.csproj", "backend/Church.API/"]
COPY ["backend/Church.Core/Church.Core.csproj", "backend/Church.Core/"]
COPY ["backend/Church.Infrastructure/Church.Infrastructure.csproj", "backend/Church.Infrastructure/"]

# Restore dependencies
RUN dotnet restore "backend/Church.API/Church.API.csproj"

# Copy full backend source
COPY backend/ backend/

# Publish release artifacts
WORKDIR "/src/backend/Church.API"
RUN dotnet publish "Church.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage using hardened ASP.NET Core image
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
EXPOSE 8080

ENV ASPNETCORE_URLS=http://+:8080 \
    DOTNET_RUNNING_IN_CONTAINER=true

# Run as non-root app user
USER $APP_UID

COPY --from=build /app/publish .

ENTRYPOINT ["dotnet", "Church.API.dll"]
