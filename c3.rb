#!/usr/bin/env ruby

class Board
  ROWS = 5
  COLS = 5
  attr_reader :grid, :history

  def initialize
    @grid = Array.new(ROWS) { Array.new(COLS, '·') }
    @row_index = Array.new(COLS, ROWS - 1)
    @history = []
  end

  def draw(clear_screen: true)
    (system('clear') || system('cls')) if clear_screen
    puts "[Connect Three]"
    puts "==============="
    
    print "  "
    (1..COLS).each { |col| print "#{col} " }
    puts
    
    ROWS.times do |i|
      row = @grid[i]
      print "#{ROWS - i}|"
      row.each { |cell| print "#{cell}|" }
      puts
    end
    
    print " +"
    (1..COLS).each { print "-+" }
    puts
    
    print "  "
    (1..COLS).each { |col| print "#{col} " }
    puts
    
    puts
  end

  def drop_piece(col, disc)
    input_col = col
    col -= 1  # 0始まりに変換
    if col < 0 || col >= @row_index.length
      return false
    end
    
    if @row_index[col] >= 0
      @grid[@row_index[col]][col] = disc
      @row_index[col] -= 1
      @history << input_col
      return true
    else
      return false  # 列が満杯
    end
  end

  def check_win(disc)
    # 横
    @grid.each do |row|
      row.each_cons(3) do |cells|
        return true if cells.all?(disc)
      end
    end

    # 縦
    (0...COLS).each do |c|
      (0...ROWS - 2).each do |r|
        return true if (0..2).all? { |k| @grid[r + k][c] == disc }
      end
    end

    # 斜め (右下がり)
    (0...ROWS - 2).each do |r|
      (0...COLS - 2).each do |c|
        return true if (0..2).all? { |k| @grid[r + k][c + k] == disc }
      end
    end

    # 斜め (左下がり)
    (2...ROWS).each do |r|
      (0...COLS - 2).each do |c|
        return true if (0..2).all? { |k| @grid[r - k][c + k] == disc }
      end
    end

    false
  end

  def available_cols
    (1..COLS).select { |c| @row_index[c-1] >= 0 }
  end

  def valid_col?(col)
    col >= 1 && col <= COLS
  end

  def unplace_piece(col)
    input_col = col
    col -= 1
    return if col < 0 || col >= @row_index.length
    
    # 直前に置かれた駒の位置を特定
    r = @row_index[col] + 1
    if r < ROWS
      @grid[r][col] = '·'
      @row_index[col] += 1
      @history.pop
    end
  end

  def deep_copy
    new_board = Board.new
    new_board.instance_variable_set(:@grid, @grid.map(&:dup))
    new_board.instance_variable_set(:@row_index, @row_index.dup)
    new_board.instance_variable_set(:@history, @history.dup)
    new_board
  end

  def grid_empty?
    @grid.all? { |row| row.all?('·') }
  end
end

class Player
  attr_reader :disc, :name

  def initialize(disc, name)
    @disc = disc
    @name = name
  end

  def get_move(board)
    raise NotImplementedError
  end
end

class HumanPlayer < Player
  def get_move(board)
    print "#{@name}の手番です。列を選択してください (1-#{Board::COLS})、終了する場合は'!': "
    input = $stdin.gets.chomp
    return :quit if input == '!'
    input.to_i
  end
end

class RandomPlayer < Player
  def get_move(board)
    available = board.available_cols
    return :draw if available.empty?
    available.sample
  end
end


class NaivePlayer < Player
  def get_move(board)
    # 先手（盤面が空）のときはあきらかに有利な中央（カラム3）に打つ
    return 3 if board.grid_empty?

    available = board.available_cols
    return :draw if available.empty?

    opponent_disc = (@disc == '●') ? '○' : '●'

    # 自分が次に勝てる手があるかチェックし、あれば打つ
    available.each do |col|
      if board.drop_piece(col, @disc)
        if board.check_win(@disc)
          board.unplace_piece(col)
          return col
        end
        board.unplace_piece(col)
      end
    end

    # 相手が次に勝つ手があるかチェックし、あれば防ぐ
    available.each do |col|
      if board.drop_piece(col, opponent_disc)
        if board.check_win(opponent_disc)
          board.unplace_piece(col)
          return col
        end
        board.unplace_piece(col)
      end
    end

    available.sample
  end
end

class IntermediatePlayer < Player
  def get_move(board)
    # 先手（盤面が空）のときはあきらかに有利な中央（カラム3）に打つ
    return 3 if board.grid_empty?

    available = board.available_cols
    return :draw if available.empty?

    best_score = -Float::INFINITY
    best_cols = []

    # 3手読み (自分 -> 相手 -> 自分)
    available.each do |col|
      board.drop_piece(col, @disc)
      # 残り深さ2 (相手 -> 自分)
      score = minimax(board, 2, false)
      board.unplace_piece(col)

      if score > best_score
        best_score = score
        best_cols = [col]
      elsif score == best_score
        best_cols << col
      end
    end

    best_cols.sample
  end

  def minimax(board, depth, is_maximizing)
    opponent_disc = (@disc == '●') ? '○' : '●'

    if board.check_win(@disc)
      return 100 + depth
    elsif board.check_win(opponent_disc)
      return -100 - depth
    end

    return 0 if depth == 0 || board.available_cols.empty?

    if is_maximizing
      scores = board.available_cols.map do |col|
        board.drop_piece(col, @disc)
        score = minimax(board, depth - 1, false)
        board.unplace_piece(col)
        score
      end
      scores.max
    else
      scores = board.available_cols.map do |col|
        board.drop_piece(col, opponent_disc)
        score = minimax(board, depth - 1, true)
        board.unplace_piece(col)
        score
      end
      scores.min
    end
  end
end

class AdvancedPlayer < Player
  def initialize(disc, name, depth = 5)
    super(disc, name)
    @depth = depth
  end

  def get_move(board)
    # 先手（盤面が空）のときはあきらかに有利な中央（カラム3）に打つ
    return 3 if board.grid_empty?

    available = board.available_cols
    return :draw if available.empty?

    best_score = -Float::INFINITY
    best_cols = []

    alpha = -Float::INFINITY
    beta = Float::INFINITY

    available.each do |col|
      board.drop_piece(col, @disc)
      score = alpha_beta(board, @depth - 1, alpha, beta, false)
      board.unplace_piece(col)

      if score > best_score
        best_score = score
        best_cols = [col]
      elsif score == best_score
        best_cols << col
      end
      alpha = [alpha, score].max
    end

    best_cols.sample
  end

  def alpha_beta(board, depth, alpha, beta, is_maximizing)
    opponent_disc = (@disc == '●') ? '○' : '●'

    if board.check_win(@disc) then return 100000 + depth end
    if board.check_win(opponent_disc) then return -100000 - depth end
    return score_board(board, @disc) if depth == 0 || board.available_cols.empty?

    if is_maximizing
      max_eval = -Float::INFINITY
      board.available_cols.each do |col|
        board.drop_piece(col, @disc)
        eval = alpha_beta(board, depth - 1, alpha, beta, false)
        board.unplace_piece(col)
        max_eval = [max_eval, eval].max
        alpha = [alpha, eval].max
        break if beta <= alpha
      end
      max_eval
    else # minimizing
      min_eval = Float::INFINITY
      board.available_cols.each do |col|
        board.drop_piece(col, opponent_disc)
        eval = alpha_beta(board, depth - 1, alpha, beta, true)
        board.unplace_piece(col)
        min_eval = [min_eval, eval].min
        beta = [beta, eval].min
        break if beta <= alpha
      end
      min_eval
    end
  end

  def score_board(board, piece)
    score = 0
    opp_piece = (piece == '●') ? '○' : '●'
    
    # 中央列の評価
    center_col = Board::COLS / 2
    center_count = board.grid.map { |r| r[center_col] }.count(piece)
    score += center_count * 3

    # 横方向
    board.grid.each do |row|
      row.each_cons(3) { |w| score += evaluate_window(w, piece, opp_piece) }
    end

    # 縦方向
    (0...Board::COLS).each do |c|
      col_array = (0...Board::ROWS).map { |r| board.grid[r][c] }
      col_array.each_cons(3) { |w| score += evaluate_window(w, piece, opp_piece) }
    end

    # 斜め (右下がり)
    (0...Board::ROWS - 2).each do |r|
      (0...Board::COLS - 2).each do |c|
        window = (0..2).map { |k| board.grid[r + k][c + k] }
        score += evaluate_window(window, piece, opp_piece)
      end
    end

    # 斜め (左下がり)
    (2...Board::ROWS).each do |r|
      (0...Board::COLS - 2).each do |c|
        window = (0..2).map { |k| board.grid[r - k][c + k] }
        score += evaluate_window(window, piece, opp_piece)
      end
    end

    score
  end

  def evaluate_window(window, piece, opp_piece)
    score = 0
    if window.count(piece) == 2 && window.count('·') == 1
      score += 10
    elsif window.count(piece) == 1 && window.count('·') == 2
      score += 2
    end

    if window.count(opp_piece) == 2 && window.count('·') == 1
      score -= 8
    elsif window.count(opp_piece) == 1 && window.count('·') == 2
      score -= 1
    end
    
    score
  end
end

class MCTSNode
  attr_accessor :move, :parent, :children, :wins, :visits, :untried_moves, :player_just_moved

  def initialize(move, parent, available_moves, player_just_moved)
    @move = move
    @parent = parent
    @children = []
    @wins = 0.0
    @visits = 0
    @untried_moves = available_moves
    @player_just_moved = player_just_moved
  end

  def select_child
    @children.max_by do |child|
      child.wins / child.visits.to_f + Math.sqrt(2 * Math.log(@visits) / child.visits.to_f)
    end
  end

  def add_child(move, available_moves, player_just_moved)
    child = MCTSNode.new(move, self, available_moves, player_just_moved)
    @children << child
    child
  end
end

class ExpertPlayer < Player
  def initialize(disc, name, iterations = 1000)
    super(disc, name)
    @iterations = iterations
  end

  def get_move(board)
    available = board.available_cols
    return :draw if available.empty?

    return 3 if board.grid_empty?

    root = MCTSNode.new(nil, nil, available, nil)
    
    @iterations.times do
      node = root
      temp_board = board.deep_copy
      current_player = @disc

      # 1. Selection
      while node.untried_moves.empty? && !node.children.empty?
        node = node.select_child
        temp_board.drop_piece(node.move, current_player)
        current_player = (current_player == '●' ? '○' : '●')
      end

      # 2. Expansion
      if !node.untried_moves.empty?
        move = node.untried_moves.sample
        node.untried_moves.delete(move)
        temp_board.drop_piece(move, current_player)
        node = node.add_child(move, temp_board.available_cols, current_player)
        current_player = (current_player == '●' ? '○' : '●')
      end

      # 3. Simulation
      sim_player = current_player
      winner = nil
      last_mover = (sim_player == '●' ? '○' : '●')
      
      if temp_board.check_win(last_mover)
        winner = last_mover
      else
        loop do
          available = temp_board.available_cols
          break if available.empty?
          move = available.sample
          temp_board.drop_piece(move, sim_player)
          if temp_board.check_win(sim_player)
            winner = sim_player
            break
          end
          sim_player = (sim_player == '●' ? '○' : '●')
        end
      end

      # 4. Backpropagation
      while node
        node.visits += 1
        if node.player_just_moved
          if winner == node.player_just_moved
            node.wins += 1
          elsif winner == nil
            node.wins += 0.5
          end
        end
        node = node.parent
      end
    end

    return board.available_cols.sample if root.children.empty?
    root.children.max_by(&:visits).move
  end
end

class PerfectPlayer < Player
  def initialize(disc, name, debug = false)
    super(disc, name)
    @debug = debug
    @node_count = 0
    @tt = {} # Transposition Table
    @first_move_done = false
  end

  def get_move(board)
    available = board.available_cols
    return :draw if available.empty?

    @node_count = 0
    @start_time = Time.now

    show_debug = false
    if @debug
      if @debug == 0
        show_debug = true
      elsif @debug == 1 && !@first_move_done
        show_debug = true
      elsif @debug == true
        show_debug = true
      end
    end

    if show_debug
      puts "\n--- 局面解析 ---"
      results = []
      
      available.each do |col|
        board.drop_piece(col, @disc)
        # 正確な評価値を得るため、Alpha-Betaウィンドウをリセットして探索
        score = minimax(board, 1, -Float::INFINITY, Float::INFINITY, false)
        board.unplace_piece(col)
        
        if score > 0
          moves = 100 - score
          puts "列 #{col}: 勝ち (#{moves}手)"
        elsif score < 0
          moves = 100 + score
          puts "列 #{col}: 負け (#{moves}手)"
        else
          puts "列 #{col}: 引き分け"
        end
        results << { col: col, score: score }
      end
      puts "----------------"
      puts "Time: #{Time.now - @start_time}s"
      
      best_score = results.map { |r| r[:score] }.max
      best_cols = results.select { |r| r[:score] == best_score }.map { |r| r[:col] }
      @first_move_done = true
      return best_cols.sample
    end

    @first_move_done = true

    best_score = -Float::INFINITY
    best_cols = []
    alpha = -Float::INFINITY
    beta = Float::INFINITY

    # 中央に近い列から探索することで、Alpha-Beta剪定の効率を上げる
    center = (Board::COLS / 2.0).ceil
    sorted_available = available.sort_by { |c| (c - center).abs }

    sorted_available.each do |col|
      board.drop_piece(col, @disc)
      # 深さ1からスタート。次は相手番(minimizing)
      # ルートノードでは正確な比較を行うため、枝刈りを無効化（ウィンドウを全開）する
      score = minimax(board, 1, -Float::INFINITY, Float::INFINITY, false)
      board.unplace_piece(col)

      if score > best_score
        best_score = score
        best_cols = [col]
      elsif score == best_score
        best_cols << col
      end
    end

    puts "Time: #{Time.now - @start_time}s" if @debug
    best_cols.sample
  end

  def minimax(board, depth, alpha, beta, is_maximizing)
    alpha_orig = alpha

    # Transposition Table Lookup
    # 盤面のハッシュをキーにする
    # 対称性を考慮して、元の盤面と左右反転した盤面のハッシュ値の小さい方をキーにする
    h1 = board.grid.hash
    h2 = board.grid.map(&:reverse).hash
    key = (h1 < h2) ? h1 : h2

    if (entry = @tt[key])
      # 深さに依存しないスコアから、現在の深さでのスコアを復元
      score = if entry[:val] > 0
                entry[:val] - depth
              elsif entry[:val] < 0
                entry[:val] + depth
              else
                0
              end

      # Alpha-Betaの境界チェック
      if entry[:type] == :exact
        return score
      elsif entry[:type] == :lower
        alpha = [alpha, score].max
      elsif entry[:type] == :upper
        beta = [beta, score].min
      end

      return score if alpha >= beta
    end

    @node_count += 1
    opponent_disc = (@disc == '●') ? '○' : '●'

    # 勝敗判定: 常に両方の勝利を確認する（安全策）
    if board.check_win(@disc)
      val = 100 - depth
      store_tt(key, val, depth, :exact)
      return val
    elsif board.check_win(opponent_disc)
      val = -100 + depth
      store_tt(key, val, depth, :exact)
      return val
    end

    available = board.available_cols
    if available.empty?
      store_tt(key, 0, depth, :exact)
      return 0
    end

    # 探索内部でも中央優先で並べ替える
    center = (Board::COLS / 2.0).ceil
    sorted_available = available.sort_by { |c| (c - center).abs }

    if is_maximizing
      max_eval = -Float::INFINITY
      sorted_available.each do |col|
        board.drop_piece(col, @disc)
        eval = minimax(board, depth + 1, alpha, beta, false)
        board.unplace_piece(col)
        max_eval = [max_eval, eval].max
        alpha = [alpha, eval].max
        break if beta <= alpha
      end
      val = max_eval
    else
      min_eval = Float::INFINITY
      sorted_available.each do |col|
        board.drop_piece(col, opponent_disc)
        eval = minimax(board, depth + 1, alpha, beta, true)
        board.unplace_piece(col)
        min_eval = [min_eval, eval].min
        beta = [beta, eval].min
        break if beta <= alpha
      end
      val = min_eval
    end

    # Store in Transposition Table
    type = :exact
    if val <= alpha_orig
      type = :upper
    elsif val >= beta
      type = :lower
    end

    store_tt(key, val, depth, type)
    val
  end

  def store_tt(key, val, depth, type)
    # 深さに依存しないスコアに変換して保存
    entry_val = if val > 0
                  val + depth
                elsif val < 0
                  val - depth
                else
                  0
                end
    @tt[key] = { type: type, val: entry_val }
  end
end

class Perfect2Player < Player
  WIN_SCORE = 10000
  BOARD_MASK = 0x104104104 # Mask for a full board (top row of each 5-row column)

  def initialize(disc, name, debug = false)
    super(disc, name)
    @debug = debug
    @node_count = 0
    @tt = {}
    @start_time = Time.now
    @tt_max_size = 100_000_000 # 100 million entries, more than enough for c3
  end

  def get_move(board)
    available = board.available_cols
    return :draw if available.empty?

    position = 0
    mask = 0
    
    (0...Board::COLS).each do |c|
      (0...Board::ROWS).each do |r|
        piece = board.grid[r][c]
        next if piece == '·'
        # bitboard height is 6 (ROWS+1)
        bit_index = (4 - r) + c * 6
        mask |= (1 << bit_index)
        if piece == @disc
          position |= (1 << bit_index)
        end
      end
    end

    @node_count = 0
    @start_time = Time.now
    @first_move_done ||= false

    show_debug = false
    if @debug
      if @debug == 0
        show_debug = true
      elsif @debug == 1 && !@first_move_done
        show_debug = true
      elsif @debug == true
        show_debug = true
      end
    end

    if show_debug
      puts "\n--- 局面解析 (BitBoard) ---"
      results = []
      
      center = (Board::COLS / 2.0).ceil
      sorted_cols = available.sort_by { |c| (c - center).abs }
      
      sorted_cols.each do |col|
        c_idx = col - 1
        move_bit = (mask & (0x3F << (c_idx * 6))) + (1 << (c_idx * 6))
        
        new_mask = mask | move_bit
        
        score = -solve(position ^ mask, new_mask, 1, -Float::INFINITY, Float::INFINITY)
        results << { col: col, score: score }
      end

      results.sort_by { |r| r[:col] }.each do |r|
        col = r[:col]
        score = r[:score]
        if score > 0
          moves = WIN_SCORE + 1 - score
          puts "列 #{col}: 勝ち (#{moves}手)"
        elsif score < 0
          moves = WIN_SCORE + 1 + score
          puts "列 #{col}: 負け (#{moves}手)"
        else
          puts "列 #{col}: 引き分け"
        end
      end
      puts "----------------"
      puts "Time: #{Time.now - @start_time}s"
      
      best_score = results.map { |r| r[:score] }.max
      best_cols = results.select { |r| r[:score] == best_score }.map { |r| r[:col] }
      @first_move_done = true
      return best_cols.sample
    end

    @first_move_done = true

    best_score = -Float::INFINITY
    best_cols = []
    alpha = -Float::INFINITY
    beta = Float::INFINITY

    center = (Board::COLS / 2.0).ceil
    sorted_cols = available.sort_by { |c| (c - center).abs }

    sorted_cols.each do |col|
      c_idx = col - 1
      move_bit = (mask & (0x3F << (c_idx * 6))) + (1 << (c_idx * 6))
      
      new_mask = mask | move_bit
      
      score = -solve(position ^ mask, new_mask, 1, alpha, beta)
      
      if score > best_score
        best_score = score
        best_cols = [col]
      elsif score == best_score
        best_cols << col
      end
      
      alpha = [alpha, score].max
    end

    puts "Time: #{Time.now - @start_time}s" if @debug
    best_cols.sample
  end

  def solve(position, mask, depth, alpha, beta)
    opponent = mask ^ position
    if check_win_bitboard(opponent)
      return -(WIN_SCORE - depth + 1)
    end

    if (mask & BOARD_MASK) == BOARD_MASK
      return 0
    end

    key = compute_key(position, mask)
    if (entry = @tt[key])
      score = entry[:val]
      if score > WIN_SCORE / 2
        score -= depth
      elsif score < -WIN_SCORE / 2
        score += depth
      end

      if entry[:type] == :exact
        return score
      elsif entry[:type] == :lower
        alpha = [alpha, score].max
      elsif entry[:type] == :upper
        beta = [beta, score].min
      end
      return score if alpha >= beta
    end

    @node_count += 1
    if @debug && @node_count % 500_000 == 0
      elapsed = Time.now - @start_time
      nps = elapsed > 0 ? (@node_count / elapsed).to_i : 0
      print "\rThinking (p2)... Nodes: #{@node_count} (NPS: #{nps})"
    end

    max_score = -Float::INFINITY
    alpha_orig = alpha

    [2, 1, 3, 0, 4].each do |c_idx|
      move_bit = (mask & (0x3F << (c_idx * 6))) + (1 << (c_idx * 6))
      next if (move_bit & (0x20 << (c_idx * 6))) != 0

      new_mask = mask | move_bit
      
      score = -solve(opponent, new_mask, depth + 1, -beta, -alpha)
      
      if score > max_score
        max_score = score
      end
      
      alpha = [alpha, score].max
      break if alpha >= beta
    end

    type = :exact
    if max_score <= alpha_orig
      type = :upper
    elsif max_score >= beta
      type = :lower
    end

    store_tt(key, max_score, depth, type)
    max_score
  end

  def check_win_bitboard(pos)
    # Vertical (3 in a row)
    m = pos & (pos >> 6)
    return true if (m & (m >> 6)) != 0
    # Horizontal
    m = pos & (pos >> 1)
    return true if (m & (m >> 1)) != 0
    # Diagonal (R)
    m = pos & (pos >> 7)
    return true if (m & (m >> 7)) != 0
    # Diagonal (L)
    m = pos & (pos >> 5)
    return true if (m & (m >> 5)) != 0
    false
  end

  def compute_key(position, mask)
    m_pos = mirror(position)
    m_mask = mirror(mask)
    k1 = position + (mask << 40)
    k2 = m_pos + (m_mask << 40)
    k1 < k2 ? k1 : k2
  end

  def mirror(b)
    c0 = b & 0x3F
    c4 = (b >> 24) & 0x3F
    c1 = (b >> 6) & 0x3F
    c3 = (b >> 18) & 0x3F
    c2 = (b >> 12) & 0x3F
    (c4) | (c3 << 6) | (c2 << 12) | (c1 << 18) | (c0 << 24)
  end

  def store_tt(key, val, depth, type)
    if @tt.size >= @tt_max_size
      @tt.shift
    end

    entry_val = val
    if val > WIN_SCORE / 2
      entry_val += depth
    elsif val < -WIN_SCORE / 2
      entry_val -= depth
    end
    @tt[key] = { type: type, val: entry_val }
  end
end

class Perfect3Player < Perfect2Player
  def initialize(disc, name, debug = false)
    super(disc, name, debug)
  end

  def get_move(board)
    # Perfect2Playerのget_moveをベースに、PVSとMove Orderingを利用する形にオーバーライド
    # ただし、ルートノードの処理はPerfect2Playerとほぼ同じで良いため、
    # 簡易的にsuperを呼び出すか、あるいはsolveメソッドが強化されているため
    # そのまま利用できる部分が多いですが、p2のget_moveはsolveを直接呼んでいます。
    # ここではp2と同じ実装を使いますが、solveがオーバーライドされるため挙動が変わります。
    super
  end

  def solve(position, mask, depth, alpha, beta)
    opponent = mask ^ position
    if check_win_bitboard(opponent)
      return -(WIN_SCORE - depth + 1)
    end

    if (mask & BOARD_MASK) == BOARD_MASK
      return 0
    end

    key = compute_key(position, mask)
    tt_move = nil

    if (entry = @tt[key])
      score = entry[:val]
      if score > WIN_SCORE / 2
        score -= depth
      elsif score < -WIN_SCORE / 2
        score += depth
      end

      # TTに保存された最善手を取得
      tt_move = entry[:best_move]

      if entry[:type] == :exact
        return score
      elsif entry[:type] == :lower
        alpha = [alpha, score].max
      elsif entry[:type] == :upper
        beta = [beta, score].min
      end
      return score if alpha >= beta
    end

    @node_count += 1
    if @debug && @node_count % 500_000 == 0
      elapsed = Time.now - @start_time
      nps = elapsed > 0 ? (@node_count / elapsed).to_i : 0
      print "\rThinking (p3)... Nodes: #{@node_count} (NPS: #{nps})"
    end

    max_score = -Float::INFINITY
    alpha_orig = alpha
    best_move_col = nil

    # 探索順序の決定: TTにある最善手を最優先、残りは中央優先
    moves = [2, 1, 3, 0, 4]
    if tt_move
      moves.delete(tt_move)
      moves.unshift(tt_move)
    end

    moves.each_with_index do |c_idx, index|
      move_bit = (mask & (0x3F << (c_idx * 6))) + (1 << (c_idx * 6))
      next if (move_bit & (0x20 << (c_idx * 6))) != 0

      new_mask = mask | move_bit
      
      # PVS (Principal Variation Search)
      if index == 0
        # 最初の手は全力で探索 (Full Window)
        score = -solve(opponent, new_mask, depth + 1, -beta, -alpha)
      else
        # 2手目以降は Null Window Search (alpha + 1)
        # 「alphaより良い手があるか？」だけをチェック
        score = -solve(opponent, new_mask, depth + 1, -alpha - 1, -alpha)
        
        # もしalphaより良い手が見つかったら、正確な値を求めて再探索
        if score > alpha && score < beta
          score = -solve(opponent, new_mask, depth + 1, -beta, -alpha)
        end
      end
      
      if score > max_score
        max_score = score
        best_move_col = c_idx
      end
      
      alpha = [alpha, score].max
      break if alpha >= beta
    end

    type = :exact
    if max_score <= alpha_orig
      type = :upper
    elsif max_score >= beta
      type = :lower
    end

    store_tt_with_move(key, max_score, depth, type, best_move_col)
    max_score
  end

  def store_tt_with_move(key, val, depth, type, best_move)
    if @tt.size >= @tt_max_size
      @tt.shift
    end

    entry_val = val
    if val > WIN_SCORE / 2
      entry_val += depth
    elsif val < -WIN_SCORE / 2
      entry_val -= depth
    end
    # best_move を追加で保存
    @tt[key] = { type: type, val: entry_val, best_move: best_move }
  end
end

class ConnectFour
  def initialize(player1, player2, wait_time = 1, display = true, debug = false)
    @board = Board.new
    @players = [player1, player2]
    @current_player_idx = 0
    @wait_time = wait_time
    @display = display
    @debug = debug
  end

  def current_player
    @players[@current_player_idx]
  end

  def switch_player
    @current_player_idx = (@current_player_idx + 1) % @players.size
  end

  def play
    loop do
      @board.draw(clear_screen: !@debug) if @display
      
      move = current_player.get_move(@board)
      
      if move == :quit
        puts "ゲームを終了します。" if @display
        return :quit
      elsif move == :draw
        puts "引き分けです！" if @display
        return :draw
      end
      
      col = move

      # バリデーション (人間の場合)
      if current_player.is_a?(HumanPlayer) && !@board.valid_col?(col)
        if @display
          puts "1から#{Board::COLS}の範囲で入力してください。"
          sleep(@wait_time)
        end
        next
      end

      if @board.drop_piece(col, current_player.disc)
        if @board.check_win(current_player.disc)
          if @display
            @board.draw(clear_screen: !@debug)
            unless current_player.is_a?(HumanPlayer)
              puts "#{current_player.name} が列 #{col} に手を指しました。"
            end
            puts "#{current_player.name} の勝ちです！"
          end
          puts "棋譜: #{@board.history.join(',')}" if @display
          return current_player
        end
        
        if @display
          unless current_player.is_a?(HumanPlayer)
            puts "#{current_player.name} が列 #{col} に手を指しました。"
            sleep(@wait_time)
          end
        end
        
        switch_player
      else
        if @display
          puts "その列は満杯です。別の列を選んでください。"
          sleep(@wait_time) if current_player.is_a?(HumanPlayer)
        end
      end
    end
    puts "棋譜: #{@board.history.join(',')}" if @display
  end
end

def create_player(type, disc, name, debug_mode = false)
  t = type.to_s.downcase
  if t =~ /^a(?:dvanced)?(\d+)?$/
    depth = $1 ? $1.to_i : 5
    return AdvancedPlayer.new(disc, name, depth)
  end
  if t =~ /^e(?:xpert)?(\d+)?$/
    iter = $1 ? $1.to_i : 1000
    return ExpertPlayer.new(disc, name, iter)
  end

  case t
  when 'human', 'h' then HumanPlayer.new(disc, name)
  when 'random', 'r' then RandomPlayer.new(disc, name)
  when 'naive', 'n' then NaivePlayer.new(disc, name)
  when 'intermediate', 'i' then IntermediatePlayer.new(disc, name)
  when 'expert', 'e' then ExpertPlayer.new(disc, name)
  when 'perfect', 'p' then PerfectPlayer.new(disc, name, debug_mode)
  when 'perfect2', 'p2' then Perfect2Player.new(disc, name, debug_mode)
  when 'perfect3', 'p3' then Perfect3Player.new(disc, name, debug_mode)
  else NaivePlayer.new(disc, name)
  end
end

def get_full_type_name(type)
  t = type.to_s.downcase
  if t =~ /^a(?:dvanced)?(\d+)?$/
    depth = $1 ? $1.to_i : 5
    return "Advanced(#{depth})"
  end
  if t =~ /^e(?:xpert)?(\d+)?$/
    iter = $1 ? $1.to_i : 1000
    return "Expert(#{iter})"
  end

  case t
  when 'human', 'h' then 'Human'
  when 'random', 'r' then 'Random'
  when 'naive', 'n' then 'Naive'
  when 'intermediate', 'i' then 'Intermediate'
  when 'expert', 'e' then 'Expert'
  when 'perfect', 'p' then 'Perfect'
  when 'perfect2', 'p2' then 'Perfect2'
  when 'perfect3', 'p3' then 'Perfect3'
  else 'Naive'
  end
end

def run_single_match(i, p1_type, p2_type, wait_time, display_mode, debug_mode = false, fixed_order = false)
  p1_desc = get_full_type_name(p1_type)
  p2_desc = get_full_type_name(p2_type)

  if fixed_order || i.even?
    player_a = create_player(p1_type, '●', "Player 1 (#{p1_desc})", debug_mode)
    player_b = create_player(p2_type, '○', "Player 2 (#{p2_desc})", debug_mode)
    game = ConnectFour.new(player_a, player_b, wait_time, display_mode, debug_mode)
    p1_obj = player_a
    p2_obj = player_b
  else
    player_a = create_player(p2_type, '●', "Player 2 (#{p2_desc})", debug_mode)
    player_b = create_player(p1_type, '○', "Player 1 (#{p1_desc})", debug_mode)
    game = ConnectFour.new(player_a, player_b, wait_time, display_mode, debug_mode)
    p1_obj = player_b
    p2_obj = player_a
  end

  if display_mode
    puts "=== 第 #{i + 1} 戦 ==="
  end

  result = game.play
  
  if result == :quit
    return :quit
  elsif result == :draw
    return :draw
  elsif result == p1_obj
    return :p1
  elsif result == p2_obj
    return :p2
  end
  :draw
end

# 引数解析
args = ARGV.dup

# -d オプション (描画なし)
d_index = args.index('-d')
display_mode = true
if d_index
  display_mode = false
  args.slice!(d_index)
end

# -v オプション (詳細デバッグ)
v_arg_index = args.find_index { |arg| arg == '-v' || arg == '-v0' }
debug_mode = false
if v_arg_index
  arg = args[v_arg_index]
  if arg == '-v'
    debug_mode = 1
  elsif arg == '-v0'
    debug_mode = 0
  end
  args.slice!(v_arg_index)
end

# -f オプション (先後固定)
f_index = args.index('-f')
fixed_order = false
if f_index
  fixed_order = true
  args.slice!(f_index)
end

# -j オプション (並列数)
j_arg_index = args.find_index { |arg| arg.start_with?('-j') }
jobs = 1
if j_arg_index
  val = args[j_arg_index][2..-1].to_i
  jobs = val > 0 ? val : 32
  args.slice!(j_arg_index)
end

match_count = 1
c_arg_index = args.find_index { |arg| arg.start_with?('-c') }
if c_arg_index
  val = args[c_arg_index][2..-1].to_i
  match_count = val if val > 0
  args.slice!(c_arg_index)
end

p1_type = args[0] || 'human'
p2_type = args[1] || 'naive'
wait_time = display_mode ? (match_count > 1 ? 0.5 : 1) : 0

results = { p1: 0, p2: 0, draw: 0 }

if jobs > 1 && match_count > 1
  # 並列実行モード
  puts "Running #{match_count} matches with #{jobs} parallel jobs..."
  
  quotient, remainder = match_count.divmod(jobs)
  pipes = []

  jobs.times do |j|
    count = quotient + (j < remainder ? 1 : 0)
    next if count == 0

    r, w = IO.pipe
    pipes << r

    fork do
      r.close
      srand # 乱数シード再初期化
      
      local_results = { p1: 0, p2: 0, draw: 0 }
      
      # 開始インデックスの計算
      start_index = 0
      (0...j).each { |prev_j| start_index += quotient + (prev_j < remainder ? 1 : 0) }

      count.times do |k|
        res = run_single_match(start_index + k, p1_type, p2_type, 0, false, debug_mode, fixed_order)
        local_results[res] += 1 if res != :quit
      end

      Marshal.dump(local_results, w)
      w.close
      exit
    end
    w.close
  end

  pipes.each do |r|
    local_res = Marshal.load(r)
    results[:p1] += local_res[:p1]
    results[:p2] += local_res[:p2]
    results[:draw] += local_res[:draw]
    r.close
  end
  
  Process.waitall
else
  # 通常実行モード
  match_count.times do |i|
    unless display_mode
      print "\rProgress: #{i + 1}/#{match_count}"
    end

    res = run_single_match(i, p1_type, p2_type, wait_time, display_mode, debug_mode, fixed_order)
    break if res == :quit
    results[res] += 1
    
    if display_mode && match_count > 1
      puts "--------------------------------"
      puts "途中経過 (#{i + 1}/#{match_count}戦):"
      puts "Player 1 (#{get_full_type_name(p1_type)}): #{results[:p1]}勝"
      puts "Player 2 (#{get_full_type_name(p2_type)}): #{results[:p2]}勝"
      puts "引き分け: #{results[:draw]}"
      puts "--------------------------------"
      sleep(3)
    elsif display_mode
      sleep(wait_time)
    end
  end
end
puts unless display_mode

puts "\n=== 通算結果 (#{match_count}戦) ==="
puts "Player 1 (#{get_full_type_name(p1_type)}): #{results[:p1]}勝"
puts "Player 2 (#{get_full_type_name(p2_type)}): #{results[:p2]}勝"
puts "引き分け: #{results[:draw]}"
