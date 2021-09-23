FROM debian:buster

ARG RIAK_VSN=3.0.7

FROM erlang:22.3.4.10 AS compile-image
ARG RIAK_VSN

RUN apt-get update && apt-get install -y libpam0g-dev

WORKDIR /usr/src
ADD https://github.com/basho/riak/archive/refs/tags/riak-${RIAK_VSN}.tar.gz source.tar.gz
RUN tar xzf source.tar.gz && rm source.tar.gz
RUN mv riak-riak-${RIAK_VSN} r
WORKDIR r

RUN ./rebar3 as rel release

FROM debian:buster AS runtime-image
ARG RIAK_VSN

RUN apt-get update && apt-get -y install libssl1.1 logrotate sudo

COPY --from=compile-image /usr/src/r/_build/rel/rel/riak /opt/riak

RUN sed -i \
    -e "s|storage_backend = bitcask|storage_backend = multi|" \
    /opt/riak/etc/riak.conf
RUN echo "buckets.default.allow_mult = true\nbuckets.default.merge_strategy = 2\n" >>/opt/riak/etc/riak.conf

RUN sed -i \
    -e "s|]\\.|, \
    {riak_kv, [ \
      {multi_backend, \
          [{be_default,riak_kv_eleveldb_backend, \
               [{max_open_files,20}]}, \
           {be_blocks,riak_kv_bitcask_backend, \
               []}]}, \
      {multi_backend_default,be_default}, \
      {multi_backend_prefix_list,[{<<\"0b:\">>,be_blocks}]}, \
      {storage_backend,riak_kv_multi_backend} \
     ]} \
     ].|" \
     /opt/riak/etc/advanced.config

EXPOSE 8087 8098 9080

RUN echo "riak soft nofile 65536\nriak hard nofile 65536\n" >>/etc/security/limits.conf

#USER riak

# We can't start riak it in CMD because at this moment as we don't yet
# know other riak nodes' addresses -- those are to be allocated by
# docker stack and need to be discovered after that.  All we can do is
# prepare the container, for a script run after docker stack deploy to
# do orchestration aid in the form of sed'ding the right values into
# riak.conf.  It is unfortunate we have to plug a sleep loop for the
# process being monitored by docker, but that's one practical solution
# I have in mind now.

CMD while :; do sleep 1m; done