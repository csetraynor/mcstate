##' Control for the pmcmc. This function constructs a list of options
##' and does some basic validation to ensure that the options will
##' work well together. Do not manually change the values in this
##' object. Do not refer to any argument except `n_steps` by position
##' as the order of the arguments may change in future.
##'
##' pMCMC is slow and you will want to parallelise it if you possibly
##' can. There are two ways of doing this which are discussed in some
##' detail in `vignette("parallelisation", package = "mcstate")`.
##'
##' @title Control for the pmcmc
##'
##' @param n_steps Number of MCMC steps to run. This is the only
##'   required argument.
##'
##' @param n_chains Optional integer, indicating the number of chains
##'   to run. If more than one then we run a series of chains and
##'   merge them with [pmcmc_combine()]. Chains are run in series,
##'   with the same filter if `n_workers` is 1, or run in parallel
##'   otherwise.
##'
##' @param n_steps_each If using workers (i.e., `n_workers > 1`), the
##'   number of steps to run in each "chunk" on each worker before
##'   reporting back to the main process. Increasing this will make
##'   progress reporting less frequent and reduce some communication
##'   overhead (though the overhead is likely to be trivial in any
##'   real application). Decreasing this will give more frequent
##'   process reporting and if `n_threads_total` is given will allow
##'   for more rapid re-allocation of unused cores once chains start
##'   finishing. The default, if not given and if `n_workers > 1` is
##'   to use 10% of `n_steps`.
##'
##' @param n_threads_total The total number of threads (i.e., cores)
##'   the total number of threads/cores to use. If `n_workers` is
##'   greater than 1 then these threads will be divided evenly across
##'   your workers at first and so `n_threads_total` must be an even
##'   multiple of `n_workers`. If chains finish at different times
##'   (including if `n_chains` is not a multiple of `n_workers`) then
##'   these threads/cores will be reallocated across workers that are
##'   still going. If `n_workers` is 1 (i.e., running in parallel) and
##'   `n_threads_total` is not given (i.e., `NULL`) we will use the
##'   number of threads specified in the particle filter
##'   creation. Otherwise this value overrides the value in the
##'   particle filter.
##'
##' @param n_workers Number of "worker" processes to use to run chains
##'   in parallel. This must be at most `n_chains` and is recommended
##'   to be a divisor of `n_chains`. If `n_workers` is 1, then chains
##'   are run in series (i.e., one chain after the other). See the
##'   parallel vignette (`vignette("parallelisation", package =
##'   "mcstate")`) for more details about this approach.
##'
##' @param rerun_every Optional integer giving the frequency at which
##'   we should rerun the particle filter on the current "accepted"
##'   state.  The default for this (`Inf`) will never rerun this
##'   point, but if you set to 100, then every 100 steps we run the
##'   particle filter on both the proposed *and* previously accepted
##'   point before doing the comparison.  This may help "unstick"
##'   chains, at the cost of some bias in the results.
##'
##' @param use_parallel_seed Logical, indicating if seeds should be
##'   configured in the same way as when running workers in parallel
##'   (with `n_workers > 1`).  Set this to `TRUE` to ensure
##'   reproducibility if you use this option sometimes (but not
##'   always). This option only has an effect if `n_workers` is 1.
##'
##' @param save_state Logical, indicating if the state should be saved
##'   at the end of the simulation. If `TRUE`, then a single
##'   randomly selected particle's state will be collected at the end
##'   of each MCMC step. This is the full state (i.e., unaffected by
##'   and `index` used in the particle filter) so that the
##'   process may be restarted from this point for projections.  If
##'   `save_trajectories` is `TRUE` the same particle will
##'   be selected for each. The default is `TRUE`, which will
##'   cause `n_state` * `n_steps` of data to be output
##'   alongside your results. Set this argument to `FALSE` to
##'   save space, or use [pmcmc_thin()] after running the
##'   MCMC.
##'
##' @param save_restart An integer vector of time points to save
##'   restart information for; this is in addition to `save_state`
##'   (which saves the final model state) and saves the full model
##'   state.  It will use the same trajectory as `save_state` and
##'   `save_trajectories`. Note that if you use this option you will
##'   end up with lots of model states and will need to process them
##'   in order to actually restart the pmcmc or the particle filter
##'   from this state. The integers correspond to the *time* variable
##'   in your filter (see [mcstate::particle_filter] for more
##'   information).
##'
##' @param save_trajectories Logical, indicating if the particle
##'   trajectories should be saved during the simulation. If `TRUE`,
##'   then a single randomly selected particle's trajectory will be
##'   collected at the end of each MCMC step.  This is the filtered
##'   state (i.e., using the `state` component of `index` provided to
##'   the particle filter).  If `save_state` is `TRUE` the same
##'   particle will be selected for each.
##'
##' @param progress Logical, indicating if a progress bar should be
##'   displayed, using [`progress::progress_bar`].
##'
##' @return A `pmcmc_control` object, which should not be modified
##'   once created.
##'
##' @export
##'
##' @examples
##' mcstate::pmcmc_control(1000)
##'
##' # Suppose we have a fairly large node with 16 cores and we want to
##' # run 8 chains. We can use all cores for a single chain and run
##' # the chains sequentially like this:
##' mcstate::pmcmc_control(1000, n_chains = 8, n_threads_total = 16)
##'
##' # However, on some platforms (e.g., Windows) this may only realise
##' # a 50% total CPU use, in which case you might benefit from
##' # splitting these chains over different worker processes (2-4
##' # workers is likely the largest useful number).
##' mcstate::pmcmc_control(1000, n_chains = 8, n_threads_total = 16,
##'                        n_workers = 4)
pmcmc_control <- function(n_steps, n_chains = 1L, n_threads_total = NULL,
                          n_workers = 1L, n_steps_each = NULL,
                          rerun_every = Inf, use_parallel_seed = FALSE,
                          save_state = TRUE, save_restart = NULL,
                          save_trajectories = FALSE, progress = FALSE) {
  assert_scalar_positive_integer(n_steps)
  assert_scalar_positive_integer(n_chains)
  assert_scalar_positive_integer(n_workers)
  if (n_workers == 1L) {
    ## Never use this in a non-parallel-worker situation
    n_steps_each <- n_steps
  } else if (is.null(n_steps_each)) {
    n_steps_each <- ceiling(n_steps / 10)
  } else {
    assert_scalar_positive_integer(n_steps_each)
  }
  if (!is.null(n_threads_total)) {
    assert_scalar_positive_integer(n_threads_total)
    if (n_threads_total < n_workers) {
      stop(sprintf("'n_threads_total' (%d) is less than 'n_workers' (%d)",
                   n_threads_total, n_workers))
    }
    if (n_threads_total %% n_workers != 0) {
      stop(sprintf(
        "'n_threads_total' (%d) is not a multiple of 'n_workers' (%d)",
        n_threads_total, n_workers))
    }
  }

  if (!identical(unname(rerun_every), Inf)) {
    assert_scalar_positive_integer(rerun_every)

  }

  assert_scalar_logical(use_parallel_seed)
  assert_scalar_logical(save_state)
  assert_scalar_logical(save_trajectories)
  assert_scalar_logical(progress)

  if (n_chains < n_workers) {
    stop(sprintf("'n_chains' (%d) is less than 'n_workers' (%d)",
                 n_chains, n_workers))
  }

  if (!is.null(save_restart)) {
    ## possibly assert_integer(save_restart)?
    assert_strictly_increasing(save_restart)
  }

  ret <- list(n_steps = n_steps,
              n_chains = n_chains,
              n_workers = n_workers,
              n_steps_each = n_steps_each,
              n_threads_total = n_threads_total,
              rerun_every = rerun_every,
              use_parallel_seed = use_parallel_seed,
              save_state = save_state,
              save_restart = save_restart,
              save_trajectories = save_trajectories,
              progress = progress)
  class(ret) <- "pmcmc_control"
  ret
}
