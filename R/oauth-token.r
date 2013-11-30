#' OAuth token objects.
#' 
#' These objects represent the complete set of data needed for OAuth access:
#' an app, an endpoint, cached credentials and parameters. They should be 
#' created through their constructor functions \code{\link{oauth1.0_token}} 
#' and \code{\link{oauth2.0_token}}.
#' 
#' @section Methods:
#' \itemize{
#'  \item \code{cache()}: caches token to disk
#'  \item \code{sign(method, url)}: returns list of url and config
#'  \item \code{refresh()}: refresh access token (if possible)
#' }
#' 
#' @section Caching:
#' OAuth tokens are cached on disk in a file called \code{.httr-oauth}
#' saved in the current working directory.  Caching is enabled if:
#' 
#' \itemize{
#' \item The session is interactive, and the user agrees to it, OR
#' \item The \code{.httr-oauth} file is already present, OR
#' \item \code{getOption("httr_oauth_cache")} is \code{TRUE}
#' }
#' 
#' You can suppress caching by setting the \code{httr_oauth_cache} option to 
#' \code{FALSE}.
#' 
#' The cache file should not be included in source code control or R packages
#' (because it contains private information), so httr will automatically add 
#' the appropriate entries to `.gitignore` and `.Rbuildignore` if needed.
#' 
#' @keywords internal
#' @importFrom methods setRefClass
#' @importFrom digest digest
#' @export
Token <- setRefClass("Token", 
  fields = c("endpoint", "app", "credentials", "params"),
  methods = list(
    initialize = function(...) {
      credentials <<- NULL
      initFields(...)
    },
    init = function(force = FALSE) {
      # Have already initialized
      if (!force && !is.null(credentials)) {
        return(.self)
      } 
      
      # Have we computed in the past?
      if (!force && use_cache()) {
        cached <- fetch_cached_token(hash())
        if (!is.null(cached)) {
          import(cached)
          return(.self)
        }
      }
      
      # Otherwise use initialise from endpoint - need to use .self to
      # force use of subclass methods
      .self$init_credentials()
      cache()
    },
    show = function() {
      cat("<OAuth> ", endpoint$authorize, "\n", sep = "")
    },
    cache = function() {
      if (!use_cache()) return()
      cache_token(.self)
      .self
    },
    hash = function() {
      digest(list(endpoint, params))
    }
  )
)

#' Generate an oauth1.0 token.
#' 
#' This is the final object in the OAuth dance - it encapsulates the app,
#' the endpoint, other parameters and the received credentials.
#' 
#' See \code{\link{Token}} for full details about the token object, and the 
#' caching policies used to store credentials across sessions.
#' 
#' @inheritParams init_oauth1.0
#' @return A \code{Token1.0} reference class (RC) object. 
#' @family OAuth
#' @export
oauth1.0_token <- function(endpoint, app, permission = NULL) {
  params <- list(permission = permission)
  Token1.0(app = app, endpoint = endpoint, params = params)$init()
}

#' @export
#' @rdname Token-ref-class
Token1.0 <- setRefClass("Token1.0", contains = "Token", methods = list(
  init_credentials = function(force = FALSE) {
    credentials <<- oauth1.0_init(endpoint, app, permission = params$permission)
  },
  refresh = function() {
    stop("Not implemented")
  }, 
  sign = function(method, url) {
    oauth_signature(url, method, app, credentials$token, 
      credentials$token_secret)
    list(url = url, config = oauth_header(oauth))    
  }
))

#' Generate an oauth2.0 token.
#' 
#' This is the final object in the OAuth dance - it encapsulates the app,
#' the endpoint, other parameters and the received credentials. It is a 
#' reference class so that it can be seemlessly updated (e.g. using 
#' \code{$refresh()}) when access expires.
#' 
#' See \code{\link{Token}} for full details about the token object, and the 
#' caching policies used to store credentials across sessions.
#' 
#' @inheritParams init_oauth2.0
#' @param as_header If \code{TRUE}, the default, sends oauth in bearer header. 
#'   If \code{FALSE}, adds as parameter to url.
#' @return A \code{Token2.0} reference class (RC) object. 
#' @family OAuth
#' @export
oauth2.0_token <- function(endpoint, app, scope = NULL, type = NULL,
                           use_oob = getOption("httr_oob_default"),
                           as_header = TRUE) {
  params <- list(scope = scope, type = type, use_oob = use_oob,
    as_header = as_header)
  Token2.0(app = app, endpoint = endpoint, params = params)$init()
}

#' @export
#' @rdname Token-ref-class
Token2.0 <- setRefClass("Token2.0", contains = "Token", methods = list(
  init_credentials = function() {
    credentials <<- init_oauth2.0(endpoint, app, scope = params$scope, 
      type = params$type, use_oob = params$use_oob)
  },
  refresh = function() {
    credentials <<- refresh_oauth2.0(endpoint, app, credentials)
    cache()
    .self
  },
  sign = function(method, url) {
    if (params$as_header) {
      config <- add_headers(Authorization = 
          paste('Bearer', credentials$access_token))
      list(url = url, config = config)
    } else {
      url <- parse_url(url)
      url$query$access_token <- credentials$access_token
      list(url = build_url(url), config = config())
    }
  }
))
