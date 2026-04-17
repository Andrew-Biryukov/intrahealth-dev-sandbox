#!/bin/bash

# ==============================================================================
# Developer Sandbox Management Script
# ==============================================================================

#amb

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
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

COMMAND=$1
TARGET=$2

# Helper function for cloning
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

# Helper to set workdir
set_workdir() {
    case "$1" in
        eshop) WORKDIR=$ESHOP_DIR; COMPOSE_FILE="docker-compose.yml" ;;
        medplum) WORKDIR=$MEDPLUM_DIR; COMPOSE_FILE="docker-compose.yml" ;;
        *) [ "$COMMAND" != "setup" ] && usage ;;
    esac
}


case "$COMMAND" in
    setup)
        echo "Initializing sandbox environments..."
        
        # --- eShopOnWeb Setup ---
        if [ "$TARGET" == "eshop" ] || [ "$TARGET" == "all" ]; then
            clone_repo "$ESHOP_REPO" "$ESHOP_DIR"
            
            echo "Patching eShopOnWeb files....."
            # Update Dockerfiles to .NET 10.0
	    # Specific Dockerfile paths provided            
	    FILE_WEB="$ESHOP_DIR/src/Web/Dockerfile"            
	    FILE_API="$ESHOP_DIR/src/PublicApi/Dockerfile"            
	    FILE_OVERRIDE="$ESHOP_DIR/docker-compose.override.yml"
	    
	    # Patch Web Dockerfile
            if [ -f "$FILE_WEB" ]; then
                sed -i 's/dotnet\/sdk:9.0/dotnet\/sdk:10.0/g' "$FILE_WEB"
                sed -i 's/dotnet\/aspnet:9.0/dotnet\/aspnet:10.0/g' "$FILE_WEB"
                echo " - $FILE_WEB updated to .NET 10.0"
            fi

            # Patch PublicApi Dockerfile
            if [ -f "$FILE_API" ]; then
                sed -i 's/dotnet\/sdk:9.0/dotnet\/sdk:10.0/g' "$FILE_API"
                sed -i 's/dotnet\/aspnet:9.0/dotnet\/aspnet:10.0/g' "$FILE_API"
                echo " - $FILE_API updated to .NET 10.0"
            fi

	    # Replace ASPNETCORE_URLS with Aspire__Seq__ServerUrl in override file            
	    if [ -f "$FILE_OVERRIDE" ]; then                
	    	sed -i 's|- ASPNETCORE_URLS=http://+:8080|- Aspire__Seq__ServerUrl=http://localhost:1111|g' "$FILE_OVERRIDE"                
	    	echo " - $FILE_OVERRIDE environment variables updated."            
	    fi
	    
        fi

        # --- Medplum Setup ---
        if [ "$TARGET" == "medplum" ] || [ "$TARGET" == "all" ]; then
            clone_repo "$MEDPLUM_REPO" "$MEDPLUM_DIR" "$MEDPLUM_TAG"
        fi
        ;;

    start)
        set_workdir "$TARGET"
        echo "Starting $TARGET sandbox..."
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" up -d --build
        ;;

    stop)
        set_workdir "$TARGET"
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" stop
        ;;

    clean)
        set_workdir "$TARGET"
        echo "Purging $TARGET environment (Clean State)..."
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" down -v --remove-orphans
        ;;

    test)
        set_workdir "$TARGET"
        echo "Running tests for $TARGET..."
        if [ "$TARGET" == "eshop" ]; then
            docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" exec -T web \
                dotnet test --logger "trx;LogFileName=../../../../results/eshop_results.trx"
        elif [ "$TARGET" == "medplum" ]; then
            docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" exec -T api \
                npm test -- --reporter json > "$RESULTS_DIR/medplum_results.json"
        fi
        ;;

    status)
        set_workdir "$TARGET"
        docker compose -f "$WORKDIR/$COMPOSE_FILE" --project-directory "$WORKDIR" ps
        ;;

    *)
        usage
        ;;
esac
