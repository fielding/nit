const c = @cImport({
    @cInclude("git2.h");
});

// Re-export all symbols
pub const git_repository = c.git_repository;
pub const git_status_list = c.git_status_list;
pub const git_status_options = c.git_status_options;
pub const git_diff = c.git_diff;
pub const git_diff_options = c.git_diff_options;
pub const git_diff_delta = c.git_diff_delta;
pub const git_diff_hunk = c.git_diff_hunk;
pub const git_diff_line = c.git_diff_line;
pub const git_revwalk = c.git_revwalk;
pub const git_commit = c.git_commit;
pub const git_object = c.git_object;
pub const git_tree = c.git_tree;
pub const git_index = c.git_index;
pub const git_oid = c.git_oid;

// Functions
pub const git_libgit2_init = c.git_libgit2_init;
pub const git_libgit2_shutdown = c.git_libgit2_shutdown;
pub const git_repository_open_ext = c.git_repository_open_ext;
pub const git_repository_free = c.git_repository_free;
pub const git_repository_index = c.git_repository_index;
pub const git_error_last = c.git_error_last;

pub const git_status_options_init = c.git_status_options_init;
pub const git_status_list_new = c.git_status_list_new;
pub const git_status_list_free = c.git_status_list_free;
pub const git_status_list_entrycount = c.git_status_list_entrycount;
pub const git_status_byindex = c.git_status_byindex;

pub const git_revwalk_new = c.git_revwalk_new;
pub const git_revwalk_free = c.git_revwalk_free;
pub const git_revwalk_push_head = c.git_revwalk_push_head;
pub const git_revwalk_sorting = c.git_revwalk_sorting;
pub const git_revwalk_next = c.git_revwalk_next;

pub const git_commit_lookup = c.git_commit_lookup;
pub const git_commit_free = c.git_commit_free;
pub const git_commit_summary = c.git_commit_summary;
pub const git_commit_time = c.git_commit_time;
pub const git_commit_tree = c.git_commit_tree;

pub const git_diff_options_init = c.git_diff_options_init;
pub const git_diff_index_to_workdir = c.git_diff_index_to_workdir;
pub const git_diff_tree_to_index = c.git_diff_tree_to_index;
pub const git_diff_free = c.git_diff_free;
pub const git_diff_print = c.git_diff_print;

pub const git_revparse_single = c.git_revparse_single;
pub const git_object_free = c.git_object_free;
pub const git_object_id = c.git_object_id;
pub const git_tree_free = c.git_tree_free;
pub const git_index_free = c.git_index_free;

pub const git_oid_tostr = c.git_oid_tostr;

// Constants
pub const GIT_STATUS_OPTIONS_VERSION = c.GIT_STATUS_OPTIONS_VERSION;
pub const GIT_STATUS_SHOW_INDEX_AND_WORKDIR = c.GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
pub const GIT_STATUS_OPT_INCLUDE_UNTRACKED = c.GIT_STATUS_OPT_INCLUDE_UNTRACKED;
pub const GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX = c.GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX;
pub const GIT_STATUS_OPT_SORT_CASE_SENSITIVELY = c.GIT_STATUS_OPT_SORT_CASE_SENSITIVELY;

pub const GIT_STATUS_INDEX_NEW = c.GIT_STATUS_INDEX_NEW;
pub const GIT_STATUS_INDEX_MODIFIED = c.GIT_STATUS_INDEX_MODIFIED;
pub const GIT_STATUS_INDEX_DELETED = c.GIT_STATUS_INDEX_DELETED;
pub const GIT_STATUS_INDEX_RENAMED = c.GIT_STATUS_INDEX_RENAMED;
pub const GIT_STATUS_INDEX_TYPECHANGE = c.GIT_STATUS_INDEX_TYPECHANGE;
pub const GIT_STATUS_WT_NEW = c.GIT_STATUS_WT_NEW;
pub const GIT_STATUS_WT_MODIFIED = c.GIT_STATUS_WT_MODIFIED;
pub const GIT_STATUS_WT_DELETED = c.GIT_STATUS_WT_DELETED;
pub const GIT_STATUS_WT_RENAMED = c.GIT_STATUS_WT_RENAMED;
pub const GIT_STATUS_WT_TYPECHANGE = c.GIT_STATUS_WT_TYPECHANGE;

pub const GIT_SORT_TIME = c.GIT_SORT_TIME;
pub const GIT_OID_SHA1_HEXSIZE = c.GIT_OID_SHA1_HEXSIZE;
pub const GIT_DIFF_OPTIONS_VERSION = c.GIT_DIFF_OPTIONS_VERSION;
pub const GIT_DIFF_INCLUDE_UNTRACKED = c.GIT_DIFF_INCLUDE_UNTRACKED;
pub const GIT_DIFF_FORMAT_PATCH = c.GIT_DIFF_FORMAT_PATCH;
