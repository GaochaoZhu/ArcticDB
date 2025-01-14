#!/bin/bash

set -e

if [[ -z "$manylinux_image" ]] ; then
    echo Resolving pinned image for cibuildwheel == \
        v${cibuildwheel_ver:?'Must set either manylinux_image or cibuildwheel_ver environment variable'}

    manylinux_image=$(curl -sL "https://github.com/pypa/cibuildwheel/raw/v${cibuildwheel_ver}/cibuildwheel/resources/pinned_docker_images.cfg" \
        | awk "/${image_grep:-manylinux2014_x86_64}/ { print \$3 ; exit }" )
    if [[ -z "$manylinux_image" ]] ; then
        echo "Failed to parse source image from cibuildwheel repo" >&2
        exit 1
    fi
fi

sccache_ver="v0.4.0-pre.9" # Temporary override as Github Actions support is in pre-release
if [[ -z "$sccache_ver" ]] ; then
    sccache_ver=`curl -sL -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
        https://api.github.com/repos/mozilla/sccache/releases/latest | jq ".tag_name"`
fi

echo "Building:
* From: ${manylinux_image}
* To: ${output_tag:="local_manylinux:latest"}
* sccache_ver=${sccache_ver}
"

cd `mktemp -d`
trap "rm -rf $PWD" EXIT

curl -o sccache.tar.gz -L https://github.com/mozilla/sccache/releases/download/$sccache_ver/sccache-$sccache_ver-x86_64-unknown-linux-musl.tar.gz
tar xvf sccache.tar.gz
mv sccache-*/sccache .
chmod 555 sccache



echo "
FROM $manylinux_image
RUN rpmkeys --import 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF' && \
    curl https://download.mono-project.com/repo/centos7-stable.repo > /etc/yum.repos.d/mono-centos7-stable.repo
ADD sccache /usr/local/bin/
RUN yum update -y && \
    yum install -y zip openssl-devel cyrus-sasl-devel devtoolset-10-libatomic-devel libcurl-devel && \
    rpm -Uvh --nodeps \$(repoquery --location mono-{core,web,devel,data,wcf,winfx}) && \
    yum clean all
" > Dockerfile

docker build -t $output_tag .
