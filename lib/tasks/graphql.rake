# bin/rails graphql:schema:idl が、スキーマの形をリポジトリの根の schema.graphql に書き出す
# （docs/architecture/graphql-schema.md「スキーマの変更と非推奨」）。
# 書き出しと schema.graphql の一致は spec/graphql/schema_dump_spec.rb が確かめる
require "graphql/rake_task"

GraphQL::RakeTask.new(schema_name: "FactoryOpsSchema", dependencies: [ :environment ], directory: File.expand_path("../..", __dir__))
