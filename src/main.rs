use rayon::prelude::*;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Instant, Duration};
use std::collections::HashMap;

const WIDTH: u32 = 7;
const HEIGHT: u32 = 6;
const SIZE: u32 = WIDTH * HEIGHT;
// エントリ数を 2^30 に設定。16byte * 2^30 = 16GB。
// 64GB環境で余裕を持って 32GB 使うなら 2 * (1 << 30) = 2^31 ですが、
// 安全のため 1 << 31 ではなく明示的な計算式にします。
const TABLE_ENTRIES: usize = 2147483648; // これで物理32GB確保
const INDEX_MASK: usize = TABLE_ENTRIES - 1;

struct Entry {
    key: AtomicU64,
    data: AtomicU64,
}

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
struct Board {
    position: u64,
    mask: u64,
    moves: u32,
}

impl Board {
    fn new() -> Self { Self { position: 0, mask: 0, moves: 0 } }
    #[inline(always)]
    fn can_play(&self, col: u32) -> bool {
        (self.mask & (1 << ((col * (HEIGHT + 1)) + HEIGHT - 1))) == 0
    }
    #[inline(always)]
    fn play(&mut self, col: u32) {
        self.position ^= self.mask;
        self.mask |= self.mask + (1 << (col * (HEIGHT + 1)));
        self.moves += 1;
    }
    #[inline(always)]
    fn is_win(&self) -> bool {
        let pos = self.position ^ self.mask;
        let directions = [1, 7, 8, 9];
        for &d in &directions {
            let m = pos & (pos >> d);
            if (m & (m >> (2 * d))) != 0 { return true; }
        }
        false
    }
    #[inline(always)]
    fn key(&self) -> u64 { self.position + self.mask }
}

#[inline(always)]
fn hash_key(mut x: u64) -> usize {
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
    x = x ^ (x >> 31);
    (x as usize) & INDEX_MASK
}

struct Solver {
    table: Arc<Vec<Entry>>,
    nodes: Arc<AtomicUsize>,
}

impl Solver {
    fn store(&self, key: u64, score: i8, best_col: u32) {
        let idx = hash_key(key);
        let data = ((best_col as u64) << 24) | ((score as u8 as u64) << 16);
        self.table[idx].key.store(key, Ordering::Relaxed);
        self.table[idx].data.store(data, Ordering::Relaxed);
    }

    fn lookup(&self, key: u64) -> (Option<i8>, Option<u32>) {
        let idx = hash_key(key);
        if self.table[idx].key.load(Ordering::Relaxed) == key {
            let data = self.table[idx].data.load(Ordering::Relaxed);
            return (Some((data >> 16) as u8 as i8), Some((data >> 24) as u32));
        }
        (None, None)
    }

    fn solve(&self, board: Board, mut alpha: i8, mut beta: i8, p_depth: u32) -> i8 {
        self.nodes.fetch_add(1, Ordering::Relaxed);
        if board.moves == SIZE { return 0; }
        let key = board.key();
        let (cached_score, best_col) = self.lookup(key);
        if let Some(score) = cached_score {
            if alpha >= beta { return score; }
        }

        let mut order = [3, 2, 4, 1, 5, 0, 6];
        if let Some(bc) = best_col {
            if bc < WIDTH {
                if let Some(pos) = order.iter().position(|&x| x == bc) {
                    order.swap(0, pos);
                }
            }
        }

        for &col in &order {
            if board.can_play(col) {
                let mut next = board;
                next.play(col);
                if next.is_win() { return (SIZE + 1 - board.moves) as i8 / 2; }
            }
        }

        let max_p = (SIZE - 1 - board.moves) as i8 / 2;
        if beta > max_p {
            beta = max_p;
            if alpha >= beta { return beta; }
        }

        let mut max_s = -22;
        let mut current_best = order[0];

        if p_depth < 4 {
            let results: Vec<(i8, u32)> = order.par_iter().filter_map(|&col| {
                if board.can_play(col) {
                    let mut next = board;
                    next.play(col);
                    Some((-self.solve(next, -beta, -alpha, p_depth + 1), col))
                } else {
                    None
                }
            }).collect();

            for (score, col) in results {
                if score > max_s { max_s = score; current_best = col; }
                if score > alpha { alpha = score; }
                if alpha >= beta { break; }
            }
        } else {
            for &col in &order {
                if board.can_play(col) {
                    let mut next = board;
                    next.play(col);
                    let score = -self.solve(next, -beta, -alpha, p_depth + 1);
                    if score > max_s { max_s = score; current_best = col; }
                    if score > alpha { alpha = score; }
                    if alpha >= beta { break; }
                }
            }
        }
        self.store(key, max_s, current_best);
        max_s
    }
}

fn main() {
    // スレッドプールを最初に一回だけ設定（エラー回避）
    let _ = rayon::ThreadPoolBuilder::new()
        .num_threads(32)
        .stack_size(16 * 1024 * 1024)
        .build_global();

    println!("Allocating and FORCE-INITIALIZING 32GB Table...");
    let start_init = Instant::now();

    // Vec::with_capacity ではなく、実際に中身を埋めて確保する
    let mut table_vec = Vec::new();
    table_vec.reserve_exact(TABLE_ENTRIES);
    
    // 物理メモリへの割り当てを確実にするため、全要素を逐次的に生成。
    // 7950Xならシングルスレッドでも数十秒で終わります。
    for _ in 0..TABLE_ENTRIES {
        table_vec.push(Entry { key: AtomicU64::new(0), data: AtomicU64::new(0) });
    }

    let solver = Arc::new(Solver {
        table: Arc::new(table_vec),
        nodes: Arc::new(AtomicUsize::new(0)),
    });

    println!("Table initialized in {:?}. Memory should be occupied.", start_init.elapsed());

    let nodes_counter = Arc::clone(&solver.nodes);
    std::thread::spawn(move || {
        let start = Instant::now();
        let mut last_nodes = 0;
        loop {
            std::thread::sleep(Duration::from_secs(30));
            let current_nodes = nodes_counter.load(Ordering::Relaxed);
            let nps = (current_nodes - last_nodes) / 30;
            println!("[Stats] Speed: {:6.2} MNPS | Total: {:11} M | Time: {:?}", 
                nps as f64 / 1_000_000.0, current_nodes / 1_000_000, start.elapsed());
            last_nodes = current_nodes;
        }
    });

    let first_moves = [3, 2, 4, 1, 5, 0, 6];
    let start_total = Instant::now();

    for &col1 in &first_moves {
        let mut b1 = Board::new();
        b1.play(col1);
        let mut tasks = Vec::new();
        for col2 in 0..WIDTH {
            if b1.can_play(col2) {
                let mut b2 = b1; b2.play(col2);
                if b2.is_win() { tasks.push((col2, 999, 21)); continue; }
                for col3 in 0..WIDTH {
                    if b2.can_play(col3) {
                        let mut b3 = b2; b3.play(col3);
                        tasks.push((col2, col3, 0));
                    }
                }
            }
        }
        let results: Vec<(u32, i8)> = tasks.into_par_iter().map(|(c2, c3, pre_score)| {
            let score = if pre_score != 0 { pre_score } else {
                let mut b3 = Board::new(); b3.play(col1); b3.play(c2); b3.play(c3);
                if b3.is_win() { 21 } else { solver.solve(b3, -22, 22, 0) }
            };
            (c2, score)
        }).collect();
        let mut min_scores = HashMap::new();
        for (c2, score) in results {
            let entry = min_scores.entry(c2).or_insert(22);
            if score < *entry { *entry = score; }
        }
        let final_score = *min_scores.values().max().unwrap_or(&0);
        let res = if final_score > 0 { format!("先手勝ち (あと {:2} 手)", final_score * 2 - 1) } 
                  else if final_score < 0 { format!("後手勝ち (あと {:2} 手)", final_score.abs() * 2) } 
                  else { "引き分け".to_string() };
        println!(">>> RESULT Column {}: {} (Total Time: {:?})", col1 + 1, res, start_total.elapsed());
    }
}
