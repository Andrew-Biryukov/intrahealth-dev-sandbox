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

#Compose files
ESHOP_COMPOSE_FILES="-f docker-compose.yml -f docker-compose.override.yml -f docker-compose.sql-health.yml"
MEDPLUM_COMPOSE_FILES="-f docker-compose.yml -f docker-compose.full-stack.yml -f docker-compose.override.yml"

#IP address detection
# 1. Try to get the real local IP
DETECTED_IP=$(hostname -I | awk '{print $1}')

# 2. Assign to SANDBOX_IP, but only if not already set by the user
# and use DETECTED_IP as the first choice, or 'localhost' as the last resort
export SANDBOX_IP=${SANDBOX_IP:-${DETECTED_IP:-localhost}}

echo "Current Sandbox IP: $SANDBOX_IP"


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

set_workdir() {
    case "$1" in
        eshop) WORKDIR=$ESHOP_DIR ;;
        medplum) WORKDIR=$MEDPLUM_DIR ;;
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

	    if [ -f "$FILE_OVERRIDE" ]; then
	    	LINE_NUM=$(grep -n -m 1 "ports:" "$FILE_OVERRIDE" | cut -d: -f1)
	    	sed -i "${LINE_NUM}i \     - Aspire__Seq__ServerUrl=http://localhost:1111" "$FILE_OVERRIDE"
             	echo " - $FILE_OVERRIDE updated (only first match patched)."
    	    fi
	    
	    #Add health check for sql server.
	    cp  eshop-docker-compose.sql-health.yml $ESHOP_DIR/docker-compose.sql-health.yml
	    echo "docker-compose.sql-health.yml is added"
        fi

        # --- Medplum Setup ---
        if [ "$TARGET" == "medplum" ] || [ "$TARGET" == "all" ]; then
            clone_repo "$MEDPLUM_REPO" "$MEDPLUM_DIR" "$MEDPLUM_TAG"
	    cp medplum-docker-compose.override.yml $MEDPLUM_DIR/docker-compose.override.yml
        fi
	
        ;;

    start)
        set_workdir "$TARGET"
        echo "Starting $TARGET sandbox from $WORKDIR..."

        case "$TARGET" in
            "eshop")
                (cd "$WORKDIR" && docker compose $ESHOP_COMPOSE_FILES up -d)
                ;;
            "medplum")
                (cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES up -d)
                ;;
            *)
                echo "Error: Unknown target '$TARGET'"
                exit 1
                ;;
        esac
        ;;    

  
    stop)
	set_workdir "$TARGET"
        echo "Stopping $TARGET sandbox from $WORKDIR..."

        case "$TARGET" in
            "eshop")
                (cd "$WORKDIR" && docker compose $ESHOP_COMPOSE_FILES down -v)
                ;;
            "medplum")
                (cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES down -v)
                ;;
            *)
                echo "Error: Unknown target '$TARGET'"
                exit 1
                ;;
        esac
        ;;


    clean)
        echo "Purging $TARGET environment (Full Reset)..."
        
        # 1. Stop and remove containers, volumes, and orphans
        if [ "$TARGET" == "all" ]; then
            # Clean eshop
            set_workdir "eshop"
	    (cd "$WORKDIR" && docker compose $ESHOP_COMPOSE_FILES down -v --remove-orphans --rmi all 2>/dev/null)
            # Clean medplum
            set_workdir "medplum"
	    (cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES down -v --remove-orphans --rmi all 2>/dev/null)
        else
            set_workdir "$TARGET"
	        case "$TARGET" in
        	    "eshop")
                	(cd "$WORKDIR" && docker compose $ESHOP_COMPOSE_FILES down -v --remove-orphans --rmi all 2>/dev/null)
                	;;
            	    "medplum")
                	(cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES down -v --remove-orphans --rmi all 2>/dev/null)
                	;;
            	    *)
                	echo "Error: Unknown target '$TARGET'"
                	exit 1
                	;;
        	esac

        fi

        # 2. Remove cloned source code
        echo "Removing source code directories..."
        if [ "$TARGET" == "eshop" ] || [ "$TARGET" == "all" ]; then
            if [ -d "$ESHOP_DIR" ]; then
                rm -rf "$ESHOP_DIR"
                echo " - $ESHOP_DIR deleted."
            fi
        fi
        
        if [ "$TARGET" == "medplum" ] || [ "$TARGET" == "all" ]; then
            if [ -d "$MEDPLUM_DIR" ]; then
                rm -rf "$MEDPLUM_DIR"
                echo " - $MEDPLUM_DIR deleted."
            fi
        fi
        
        echo "Cleanup complete. System is in a 'Ready to Setup' state."
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
        case "$TARGET" in
       	    "eshop")
               	(cd "$WORKDIR" && docker compose $ESHOP_COMPOSE_FILES ps)
               	;;
       	    "medplum")
               	(cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES ps)
               	;;
            *)
               	echo "Error: Unknown target '$TARGET'"
               	exit 1
               	;;
        esac
        ;;

    *)
        usage
        ;;
esac
