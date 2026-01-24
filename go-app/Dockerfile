FROM golang:1.22-alpine AS build
WORKDIR /app
COPY main.go .
COPY go.mod .
COPY go.sum .
RUN go build -o app

FROM alpine:3.19
WORKDIR /app
COPY --from=build /app/app .
EXPOSE 8080
CMD ["./app"]
