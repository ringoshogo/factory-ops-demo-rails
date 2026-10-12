module Imports
  # 失敗した置き場の行。message は「列名: 理由」の形で、行全体の誤りは列名を持たない
  ImportRowErrorValue = Data.define(:row_number, :message)
end
