FROM postgres:17-alpine
COPY pg_cron.tar.gz /tmp/pg_cron.tar.gz
RUN apk add --no-cache build-base \
 && mkdir /tmp/pg_cron \
 && tar -xzf /tmp/pg_cron.tar.gz --strip-components=1 -C /tmp/pg_cron \
 && make -C /tmp/pg_cron PG_CONFIG=/usr/local/bin/pg_config with_llvm=no \
 && make -C /tmp/pg_cron PG_CONFIG=/usr/local/bin/pg_config with_llvm=no install \
 && rm -rf /tmp/pg_cron /tmp/pg_cron.tar.gz
CMD ["postgres", "-c", "shared_preload_libraries=pg_cron", "-c", "cron.database_name=postgres", "-c", "cron.use_background_workers=on"]
