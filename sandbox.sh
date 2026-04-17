#!/bin/bash

# ==============================================================================
# Developer Sandbox Management Script
# ==============================================================================

# Configuration
PROJECTS_DIR="./projects"
ESHOP_DIR="$PROJECTS_DIR/eShopOnWeb"
MEDPLUM_DIR="$PROJECTS_DIR/medplum"
RESULTS_DIR="./results"

# Repository URLs
ESHOP_REPO="https://github.com/NimblePros/eShopOnWeb.git"
MEDPLUM_REPO="https://github.com/medplum/medplum.git"
MEDPLUM_TAG="v5.1.8"

# Ensure core directories exist
mkdir -p "$PROJECTS_DIR"
mkdir -p "$RESULTS_DIR"

usage() {
    echo "Usage: $0 {setup|start|stop|clean|test|status} {eshop|medplum|all}"
    echo "Examples:"
    echo "  $0 setup all      # Clones all repositories"
    echo "  $0 start eshop    # Starts eShopOnWeb environment"
    echo "  $0 test medplum   # Runs Medplum tests and captures output"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

COMMAND=$1
TARGET=$2

# Helper function for cloning repositories
clone_repo() {
    local repo_url=$1
    local target_dir=$2
    local branch=$3

    if [ ! -d "$target_dir" ]; then
        if [ -n "$branch" ]; then
            echo "Cloning $(basename "$target_dir") (Version: $branch)..."
            git clone --branch "$branch" --depth 1 "$repo_url" "$target_dir"
        else
            echo "Cloning $(basename "$target_dir") (Latest)..."
            git clone --depth 1 "$repo_url" "$target_dir"
        fi
    else
        echo "Directory $(basename "$target_dir") already exists. Skipping clone."
    fi
}

# Map target to working directory and determine compose file
set_workdir() {
    case "$1" in
        eshop)
            WORKDIR=$ESHOP_DIR
            COMPOSE_FILE="docker-compose.yml"
            ;;
        medplum)
            WORKDIR=$MEDPLUM_DIR
            COMPOSE_FILE="docker-compose.yml"
            ;;
        *)
            if [ "$COMMAND" != "setup" ]; then
                echo "Error: Target '$1' is not supported for command '$COMMAND'"
                usage
            fi
            ;;
    esac
}

case "$COMMAND" in
    setup)
        echo "Initializing sandbox environments..."
        if [ "$TARGET" == "eshop" ] || [ "$TARGET" == "all" ]; then
            clone_repo "$ESHOP_REPO" "$ESHOP_DIR"
        fi
        if [ "$TARGET" == "medplum" ] || [ "$TARGET" == "all" ]; then
            clone_repo "$MEDPLUM_REPO" "$MEDPLUM_DIR" "$MEDPLUM_TAG"
        fi
        ;;

    start)
        set_workdir "$TARGET"
        echo "Starting $TARGET sandbox..."
        # --build ensures AI-generated code changes are incorporated
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" up -d --build
        ;;

    stop)
        set_workdir "$TARGET"
        echo "Stopping $TARGET containers..."
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" stop
        ;;

    clean)
        set_workdir "$TARGET"
        echo "Purging $TARGET environment (Ensuring Clean State)..."
        # -v removes volumes to guarantee database schema reset
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" down -v --remove-orphans
        ;;

    test)
        set_workdir "$TARGET"
        echo "Executing non-interactive test suite for $TARGET..."
        if [ "$TARGET" == "eshop" ]; then
            # Run .NET tests and export to TRX (XML) format for structured capture
            docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" exec -T web \
                dotnet test --logger "trx;LogFileName=../../../../results/eshop_results.trx"
        elif [ "$TARGET" == "medplum" ]; then
            # Run Node.js tests and capture JSON output for AI consumption
            docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" exec -T api \
                npm test -- --reporter json > "$RESULTS_DIR/medplum_results.json"
        fi
        echo "Test results saved to $RESULTS_DIR"
        ;;

    status)
        set_workdir "$TARGET"
        echo "Current status for $TARGET:"
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" ps
        ;;

    *)
        usage
        ;;
esac
