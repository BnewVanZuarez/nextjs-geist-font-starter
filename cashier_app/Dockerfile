# Use the official Flutter image as the base image
FROM cirrusci/flutter:stable

# Set the working directory
WORKDIR /app

# Copy the entire project
COPY . .

# Install dependencies
RUN flutter pub get

# Build the app for web
RUN flutter build web

# Use nginx to serve the web app
FROM nginx:alpine

# Copy the built web app to nginx
COPY --from=0 /app/build/web /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 8000
EXPOSE 8000

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
