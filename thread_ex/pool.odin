package thread_ex

import "core:thread"

pool_wait_all :: proc(pool: ^thread.Pool) {
	for 0 < thread.pool_num_outstanding(pool) {
		thread.yield()
	}
	for {
		thread.pool_pop_done(pool) or_break
	}
}