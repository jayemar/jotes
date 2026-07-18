# Expects `flutter build web --release` to have already been run (see
# .github/workflows/publish-web-image.yml) so build/web exists - this image
# only serves the pre-built static output, it doesn't contain the Flutter
# SDK or build toolchain.
FROM nginx:alpine
COPY build/web /usr/share/nginx/html
EXPOSE 80
