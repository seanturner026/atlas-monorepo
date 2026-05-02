FROM arigaio/atlas:latest AS atlas

FROM gcr.io/distroless/static:nonroot

ARG SERVICE_NAME

WORKDIR /

COPY --from=atlas /atlas /atlas
COPY atlas.hcl /atlas.hcl
COPY db/${SERVICE_NAME}/migrations /migrations

ENTRYPOINT ["/atlas"]
CMD ["migrate", "apply", "--config", "file:///atlas.hcl", "--env", "default"]
