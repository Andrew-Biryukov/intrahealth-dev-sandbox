#!/bin/bash

# Configuration
PROJECTS_DIR="./projects"
ESHOP_DIR="$PROJECTS_DIR/eShopOnWeb"
MEDPLUM_DIR="$PROJECTS_DIR/medplum"
RESULTS_DIR="./results"

# Create results dir if not exists
mkdir -p "$RESULTS_DIR"

usage() {
    echo "Usage: $0 {start|stop|clean|test|status} {eshop|medplum}"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

COMMAND=$1
TARGET=$2

# Map target to directory and compose file
if [ "$TARGET" == "eshop" ]; then
    WORKDIR=$ESHOP_DIR
    COMPOSE_FILE="docker-compose.yml" # Или твой кастомный
elif [ "$TARGET" == "medplum" ]; then
    WORKDIR=$MEDPLUM_DIR
    COMPOSE_FILE="docker-compose.yml"
else
    usage
fi

case "$COMMAND" in
    start)
        echo "Starting $TARGET..."
        # Используем --build чтобы подхватывать изменения кода от AI-агента
        docker compose -f "$WORKDIR/$COMPOSE_FILE" up -d --build
        ;;
    stop)
        echo "Stopping $TARGET..."
        docker compose -f "$WORKDIR/$COMPOSE_FILE" stop
        ;;
    clean)
        echo "Destroying $TARGET (Clean State)..."
        # -v критически важен для удаления БД и чистого старта
        docker compose -f "$WORKDIR/$COMPOSE_FILE" down -v --remove-orphans
        ;;
    test)
        echo "Running tests for $TARGET..."
        if [ "$TARGET" == "eshop" ]; then
            # Пример запуска тестов внутри контейнера и экспорт результатов
            docker compose -f "$WORKDIR/$COMPOSE_FILE" exec -T web dotnet test --logger "trx;LogFileName=../../../../results/eshop_results.trx"
        else
            # Для Medplum (npm)
            docker compose -f "$WORKDIR/$COMPOSE_FILE" exec -T api npm test -- --reporter json > "$RESULTS_DIR/medplum_results.json"
        fi
        ;;
    status)
        docker compose -f "$WORKDIR/$COMPOSE_FILE" ps
        ;;
    *)
        usage
        ;;
esac
