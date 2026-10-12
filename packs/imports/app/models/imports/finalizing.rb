module Imports
  # 締める段階。反映を終えた取り込みに終わりの時刻を書き、ファイルの中身を消す。終えた取り込みには何も書かないので、
  # 同じ取り込みの 2 つのジョブが締めても、終わりの時刻とイベントは 1 回になる
  module Finalizing
    def self.run(import_id, tenant_id)
      Chunk.locked(import_id, tenant_id) do |import|
        import.update!(finished_at: Time.current)
        Chunk.finish!(import)
      end
    end
  end
end
