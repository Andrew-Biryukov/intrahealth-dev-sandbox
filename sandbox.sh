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

#Postgres volume backup parameters
PG_CONTAINER_NAME="medplum-postgres-1"
PG_VOLUME_NAME="medplum_medplum-postgres-data"
PG_VOLUME_BACKUP_FILE="medplum_db_backup.tar.gz"


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
		echo "eShopOnWeb is available by the following URLs:
http://$SANDBOX_IP:5106
http://$SANDBOX_IP:5106/health
http://$SANDBOX_IP:5200/swagger
" 
                ;;
            "medplum")
		
		if [ -f "$PG_VOLUME_BACKUP_FILE" ]; then
			echo "Postgres volume backup file $PG_VOLUME_BACKUP_FILE was found, restoring volume from backup"
			echo "Create empty volume $PG_VOLUME_NAME"
			docker volume create $PG_VOLUME_NAME
			echo "Add PG files to the volume"
			docker run --rm -v $PG_VOLUME_NAME:/dest -v $(pwd):/backup alpine sh -c "tar xzf /backup/$PG_VOLUME_BACKUP_FILE -C /dest"
		fi

                (cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES up -d)


		if [ ! -f  "$PG_VOLUME_BACKUP_FILE" ]; then
			echo "Postgres volume backup file $PG_VOLUME_BACKUP_FILE was not found, creating volume backup"
			SUCCESS_COUNT=0
			REQUIRED_SUCCESSES=5
			echo "Waiting for PostgreSQL to stay idle for $REQUIRED_SUCCESSES consecutive checks..."
			while [ $SUCCESS_COUNT -lt $REQUIRED_SUCCESSES ]; do
    				# Capture clean numeric output
    				ACTIVE_QUERIES=$(docker exec $PG_CONTAINER_NAME psql -U medplum -t -A -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null)

				# Check if we got a valid number and it's equal to 1
    				if [[ "$ACTIVE_QUERIES" =~ ^[0-9]+$ ]] && [ "$ACTIVE_QUERIES" -eq 1 ]; then
        				((SUCCESS_COUNT++))
        				echo "[$(date +%T)] Idle check $SUCCESS_COUNT/$REQUIRED_SUCCESSES passed."
    				else
        				# Reset counter if database becomes active again
        				if [ $SUCCESS_COUNT -gt 0 ]; then
            					echo "[$(date +%T)] Activity detected! Resetting counter."
        				fi
        				SUCCESS_COUNT=0
        				echo "[$(date +%T)] Active queries: ${ACTIVE_QUERIES:-error}. Waiting..."
    				fi
				# Wait for 3 seconds before next check
    				sleep 1
			done

			echo "Database confirmed idle. Proceeding..."
			echo "docker compose pause"
			(cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES pause)
			echo "create postgres volume backup in file medplum_db_backup.tar.gz"
			docker run --rm -v $PG_VOLUME_NAME:/source -v $(pwd):/backup alpine tar czf /backup/$PG_VOLUME_BACKUP_FILE -C /source .
			echo "docker compose unpause"
			(cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES unpause)
		fi
		
		echo "medplum is available by the following URLs:  
http://$SANDBOX_IP:3000   
http://$SANDBOX_IP:8103/healthcheck
" 
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
                (cd "$WORKDIR" && docker compose $ESHOP_COMPOSE_FILES down)
                ;;
            "medplum")
                (cd "$WORKDIR" && docker compose $MEDPLUM_COMPOSE_FILES stop)
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

        # 2. Remove cloned source code and volume backup
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
		if [ -f "$PG_VOLUME_BACKUP_FILE" ]; then 
			rm -rf $PG_VOLUME_BACKUP_FILE
			echo "Postgres volume baclup file $PG_VOLUME_BACKUP_FILE is deleted"
		fi				
            fi
        fi

	IMAGE_NAME="alpine:latest"
	if [ -n "$(docker images -q $IMAGE_NAME)" ]; then
	    echo "Image $IMAGE_NAME found. Removing..."
	    docker rmi "$IMAGE_NAME"
    	    echo "Image $IMAGE_NAME is deleted."
	fi
        echo "Cleanup complete. System is in a 'Ready to Setup' state."
        ;;

    test)
        set_workdir "$TARGET"
        echo "Running tests for $TARGET..."
        
        if [ "$TARGET" == "eshop" ]; then
            (cd "$WORKDIR" && docker compose -f "$ESHOP_COMPOSE_FILES" --project-directory "$WORKDIR" exec -T web \
                dotnet test --logger "trx;LogFileName=results/eshop_results.trx")
                
        elif [ "$TARGET" == "medplum" ]; then
             (cd "$WORKDIR" && docker compose -f "$MEDPLUM_COMPOSE_FILES" --project-directory "$WORKDIR" exec -T api \
                npm test -- --reporter json > "$RESULTS_DIR/medplum_results.json")
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
