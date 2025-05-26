#!/bin/bash

# Exit on any error
set -e

# Help message
show_help() {
    echo "Docker Helper Script for Kasir App"
    echo
    echo "Usage: ./scripts/docker.sh [command]"
    echo
    echo "Commands:"
    echo "  start       Start the application in production mode"
    echo "  dev        Start the application in development mode with hot-reload"
    echo "  test       Run tests in Docker container"
    echo "  build      Build Docker images"
    echo "  stop       Stop all running containers"
    echo "  clean      Remove all containers and images"
    echo "  logs       Show container logs"
    echo "  shell      Open a shell in the running container"
    echo "  help       Show this help message"
    echo
    echo "Examples:"
    echo "  ./scripts/docker.sh start"
    echo "  ./scripts/docker.sh dev"
    echo "  ./scripts/docker.sh test"
}

# Check if .env file exists
check_env() {
    if [ ! -f .env ]; then
        echo "Creating .env file from example..."
        cp .env.example .env
        echo "Please update .env with your credentials."
        exit 1
    fi
}

# Start production mode
start_prod() {
    check_env
    echo "Starting Kasir App in production mode..."
    docker-compose up -d web
    echo "App is running at http://localhost:8000"
}

# Start development mode
start_dev() {
    check_env
    echo "Starting Kasir App in development mode..."
    docker-compose up web-dev
}

# Run tests
run_tests() {
    echo "Running tests in Docker container..."
    docker-compose run --rm test
}

# Build images
build_images() {
    echo "Building Docker images..."
    docker-compose build
}

# Stop containers
stop_containers() {
    echo "Stopping containers..."
    docker-compose down
}

# Clean up
clean_up() {
    echo "Cleaning up Docker resources..."
    docker-compose down -v --rmi all
}

# Show logs
show_logs() {
    echo "Showing container logs..."
    docker-compose logs -f
}

# Open shell
open_shell() {
    echo "Opening shell in web container..."
    docker-compose exec web sh
}

# Main script logic
case "$1" in
    "start")
        start_prod
        ;;
    "dev")
        start_dev
        ;;
    "test")
        run_tests
        ;;
    "build")
        build_images
        ;;
    "stop")
        stop_containers
        ;;
    "clean")
        clean_up
        ;;
    "logs")
        show_logs
        ;;
    "shell")
        open_shell
        ;;
    "help"|"")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo
        show_help
        exit 1
        ;;
esac

exit 0
