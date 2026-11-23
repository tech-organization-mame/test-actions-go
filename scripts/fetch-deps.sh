#!/usr/bin/env bash
echo "go: downloading github.com/example/dep v1.2.3"
echo 'go: github.com/example/dep@v1.2.3: Get "https://proxy.example.net/github.com/example/dep/@v/v1.2.3.zip": dial tcp 203.0.113.10:443: i/o timeout' >&2
echo "note: temporary failure, retrying (1/3)" >&2
echo "note: temporary failure, retrying (2/3)" >&2
echo "note: giving up after 3 attempts" >&2
exit 1
