require "cases/helper"
require 'models/post'
require 'models/topic'
require 'models/comment'
require 'models/reply'
require 'models/author'
require 'models/developer'

class NamedScopeTest < ActiveRecord::TestCase
  fixtures :posts, :authors, :topics, :comments, :author_addresses

  def test_implements_enumerable
    assert !Topic.all.empty?

    assert_equal Topic.all,   Topic.base
    assert_equal Topic.all,   Topic.base.to_a
    assert_equal Topic.first, Topic.base.first
    assert_equal Topic.all,   Topic.base.map { |i| i }
  end

  def test_found_items_are_cached
    all_posts = Topic.base

    assert_queries(1) do
      all_posts.collect
      all_posts.collect
    end
  end

  def test_reload_expires_cache_of_found_items
    all_posts = Topic.base
    all_posts.all

    new_post = Topic.create!
    assert !all_posts.include?(new_post)
    assert all_posts.reload.include?(new_post)
  end

  def test_delegates_finds_and_calculations_to_the_base_class
    assert !Topic.all.empty?

    assert_equal Topic.all,               Topic.base.all
    assert_equal Topic.first,             Topic.base.first
    assert_equal Topic.count,                    Topic.base.count
    assert_equal Topic.average(:replies_count), Topic.base.average(:replies_count)
  end

  def test_method_missing_priority_when_delegating
    klazz = Class.new(ActiveRecord::Base) do
      self.table_name = "topics"
      scope :since, Proc.new { where('written_on >= ?', Time.now - 1.day) }
      scope :to,    Proc.new { where('written_on <= ?', Time.now) }
    end
    assert_equal klazz.to.since.all, klazz.since.to.all
  end

  def test_scope_should_respond_to_own_methods_and_methods_of_the_proxy
    assert Topic.approved.respond_to?(:limit)
    assert Topic.approved.respond_to?(:count)
    assert Topic.approved.respond_to?(:length)
  end

  def test_respond_to_respects_include_private_parameter
    assert !Topic.approved.respond_to?(:tables_in_string)
    assert Topic.approved.respond_to?(:tables_in_string, true)
  end

  def test_scopes_with_options_limit_finds_to_those_matching_the_criteria_specified
    assert !Topic.scoped(:where => {:approved => true}).all.empty?

    assert_equal Topic.scoped(:where => {:approved => true}).all, Topic.approved
    assert_equal Topic.where(:approved => true).count, Topic.approved.count
  end

  def test_scopes_with_string_name_can_be_composed
    # NOTE that scopes defined with a string as a name worked on their own
    # but when called on another scope the other scope was completely replaced
    assert_equal Topic.replied.approved, Topic.replied.approved_as_string
  end

  def test_scopes_are_composable
    assert_equal((approved = Topic.scoped(:where => {:approved => true}).all), Topic.approved)
    assert_equal((replied = Topic.scoped(:where => 'replies_count > 0').all), Topic.replied)
    assert !(approved == replied)
    assert !(approved & replied).empty?

    assert_equal approved & replied, Topic.approved.replied
  end

  def test_procedural_scopes
    topics_written_before_the_third = Topic.where('written_on < ?', topics(:third).written_on)
    topics_written_before_the_second = Topic.where('written_on < ?', topics(:second).written_on)
    assert_not_equal topics_written_before_the_second, topics_written_before_the_third

    assert_equal topics_written_before_the_third, Topic.written_before(topics(:third).written_on)
    assert_equal topics_written_before_the_second, Topic.written_before(topics(:second).written_on)
  end

  def test_procedural_scopes_returning_nil
    all_topics = Topic.all

    assert_equal all_topics, Topic.written_before(nil)
  end

  def test_scope_with_object
    objects = Topic.with_object
    assert_operator objects.length, :>, 0
    assert objects.all?(&:approved?), 'all objects should be approved'
  end

  def test_has_many_associations_have_access_to_scopes
    assert_not_equal Post.containing_the_letter_a, authors(:david).posts
    assert !Post.containing_the_letter_a.empty?

    assert_equal authors(:david).posts & Post.containing_the_letter_a, authors(:david).posts.containing_the_letter_a
  end

  def test_scope_with_STI
    assert_equal 3,Post.containing_the_letter_a.count
    assert_equal 1,SpecialPost.containing_the_letter_a.count
  end

  def test_has_many_through_associations_have_access_to_scopes
    assert_not_equal Comment.containing_the_letter_e, authors(:david).comments
    assert !Comment.containing_the_letter_e.empty?

    assert_equal authors(:david).comments & Comment.containing_the_letter_e, authors(:david).comments.containing_the_letter_e
  end

  def test_scopes_honor_current_scopes_from_when_defined
    assert !Post.ranked_by_comments.limit_by(5).empty?
    assert !authors(:david).posts.ranked_by_comments.limit_by(5).empty?
    assert_not_equal Post.ranked_by_comments.limit_by(5), authors(:david).posts.ranked_by_comments.limit_by(5)
    assert_not_equal Post.top(5), authors(:david).posts.top(5)
    # Oracle sometimes sorts differently if WHERE condition is changed
    assert_equal authors(:david).posts.ranked_by_comments.limit_by(5).to_a.sort_by(&:id), authors(:david).posts.top(5).to_a.sort_by(&:id)
    assert_equal Post.ranked_by_comments.limit_by(5), Post.top(5)
  end

  def test_active_records_have_scope_named__all__
    assert !Topic.all.empty?

    assert_equal Topic.all, Topic.base
  end

  def test_active_records_have_scope_named__scoped__
    scope = Topic.where("content LIKE '%Have%'")
    assert !scope.empty?

    assert_equal scope, Topic.scoped(where: "content LIKE '%Have%'")
  end

  def test_first_and_last_should_allow_integers_for_limit
    assert_equal Topic.base.first(2), Topic.base.to_a.first(2)
    assert_equal Topic.base.last(2), Topic.base.order("id").to_a.last(2)
  end

  def test_first_and_last_should_not_use_query_when_results_are_loaded
    topics = Topic.base
    topics.reload # force load
    assert_no_queries do
      topics.first
      topics.last
    end
  end

  def test_empty_should_not_load_results
    topics = Topic.base
    assert_queries(2) do
      topics.empty?  # use count query
      topics.collect # force load
      topics.empty?  # use loaded (no query)
    end
  end

  def test_any_should_not_load_results
    topics = Topic.base
    assert_queries(2) do
      topics.any?    # use count query
      topics.collect # force load
      topics.any?    # use loaded (no query)
    end
  end

  def test_any_should_call_proxy_found_if_using_a_block
    topics = Topic.base
    assert_queries(1) do
      topics.expects(:empty?).never
      topics.any? { true }
    end
  end

  def test_any_should_not_fire_query_if_scope_loaded
    topics = Topic.base
    topics.collect # force load
    assert_no_queries { assert topics.any? }
  end

  def test_model_class_should_respond_to_any
    assert Topic.any?
    Topic.delete_all
    assert !Topic.any?
  end

  def test_many_should_not_load_results
    topics = Topic.base
    assert_queries(2) do
      topics.many?   # use count query
      topics.collect # force load
      topics.many?   # use loaded (no query)
    end
  end

  def test_many_should_call_proxy_found_if_using_a_block
    topics = Topic.base
    assert_queries(1) do
      topics.expects(:size).never
      topics.many? { true }
    end
  end

  def test_many_should_not_fire_query_if_scope_loaded
    topics = Topic.base
    topics.collect # force load
    assert_no_queries { assert topics.many? }
  end

  def test_many_should_return_false_if_none_or_one
    topics = Topic.base.where(:id => 0)
    assert !topics.many?
    topics = Topic.base.where(:id => 1)
    assert !topics.many?
  end

  def test_many_should_return_true_if_more_than_one
    assert Topic.base.many?
  end

  def test_model_class_should_respond_to_many
    Topic.delete_all
    assert !Topic.many?
    Topic.create!
    assert !Topic.many?
    Topic.create!
    assert Topic.many?
  end

  def test_should_build_on_top_of_scope
    topic = Topic.approved.build({})
    assert topic.approved
  end

  def test_should_build_new_on_top_of_scope
    topic = Topic.approved.new
    assert topic.approved
  end

  def test_should_create_on_top_of_scope
    topic = Topic.approved.create({})
    assert topic.approved
  end

  def test_should_create_with_bang_on_top_of_scope
    topic = Topic.approved.create!({})
    assert topic.approved
  end

  def test_should_build_on_top_of_chained_scopes
    topic = Topic.approved.by_lifo.build({})
    assert topic.approved
    assert_equal 'lifo', topic.author_name
  end

  def test_find_all_should_behave_like_select
    assert_equal Topic.base.to_a.select(&:approved), Topic.base.to_a.find_all(&:approved)
  end

  def test_rand_should_select_a_random_object_from_proxy
    assert_kind_of Topic, Topic.approved.sample
  end

  def test_should_use_where_in_query_for_scope
    assert_equal Developer.where(name: 'Jamis').to_set, Developer.where(id: Developer.jamises).to_set
  end

  def test_size_should_use_count_when_results_are_not_loaded
    topics = Topic.base
    assert_queries(1) do
      assert_sql(/COUNT/i) { topics.size }
    end
  end

  def test_size_should_use_length_when_results_are_loaded
    topics = Topic.base
    topics.reload # force load
    assert_no_queries do
      topics.size # use loaded (no query)
    end
  end

  def test_should_not_duplicates_where_values
    where_values = Topic.where("1=1").scope_with_lambda.where_values
    assert_equal ["1=1"], where_values
  end

  def test_chaining_with_duplicate_joins
    join = "INNER JOIN comments ON comments.post_id = posts.id"
    post = Post.find(1)
    assert_equal post.comments.size, Post.joins(join).joins(join).where("posts.id = #{post.id}").size
  end

  def test_chaining_should_use_latest_conditions_when_creating
    post = Topic.rejected.new
    assert !post.approved?

    post = Topic.rejected.approved.new
    assert post.approved?

    post = Topic.approved.rejected.new
    assert !post.approved?

    post = Topic.approved.rejected.approved.new
    assert post.approved?
  end

  def test_chaining_should_use_latest_conditions_when_searching
    # Normal hash conditions
    assert_equal Topic.where(:approved => true).to_a, Topic.rejected.approved.all
    assert_equal Topic.where(:approved => false).to_a, Topic.approved.rejected.all

    # Nested hash conditions with same keys
    assert_equal [posts(:sti_comments)], Post.with_special_comments.with_very_special_comments.all

    # Nested hash conditions with different keys
    assert_equal [posts(:sti_comments)], Post.with_special_comments.with_post(4).all.uniq
  end

  def test_scopes_batch_finders
    assert_equal 3, Topic.approved.count

    assert_queries(4) do
      Topic.approved.find_each(:batch_size => 1) {|t| assert t.approved? }
    end

    assert_queries(2) do
      Topic.approved.find_in_batches(:batch_size => 2) do |group|
        group.each {|t| assert t.approved? }
      end
    end
  end

  def test_table_names_for_chaining_scopes_with_and_without_table_name_included
    assert_nothing_raised do
      Comment.for_first_post.for_first_author.all
    end
  end

  def test_scopes_on_relations
    # Topic.replied
    approved_topics = Topic.scoped.approved.order('id DESC')
    assert_equal topics(:fourth), approved_topics.first

    replied_approved_topics = approved_topics.replied
    assert_equal topics(:third), replied_approved_topics.first
  end

  def test_index_on_scope
    approved = Topic.approved.order('id ASC')
    assert_equal topics(:second), approved[0]
    assert approved.loaded?
  end

  def test_nested_scopes_queries_size
    assert_queries(1) do
      Topic.approved.by_lifo.replied.written_before(Time.now).all
    end
  end

  # Note: these next two are kinda odd because they are essentially just testing that the
  # query cache works as it should, but they are here for legacy reasons as they was previously
  # a separate cache on association proxies, and these show that that is not necessary.
  def test_scopes_are_cached_on_associations
    post = posts(:welcome)

    Post.cache do
      assert_queries(1) { post.comments.containing_the_letter_e.all }
      assert_no_queries { post.comments.containing_the_letter_e.all }
    end
  end

  def test_scopes_with_arguments_are_cached_on_associations
    post = posts(:welcome)

    Post.cache do
      one = assert_queries(1) { post.comments.limit_by(1).all }
      assert_equal 1, one.size

      two = assert_queries(1) { post.comments.limit_by(2).all }
      assert_equal 2, two.size

      assert_no_queries { post.comments.limit_by(1).all }
      assert_no_queries { post.comments.limit_by(2).all }
    end
  end

  def test_scopes_to_get_newest
    post = posts(:welcome)
    old_last_comment = post.comments.newest
    new_comment = post.comments.create(:body => "My new comment")
    assert_equal new_comment, post.comments.newest
    assert_not_equal old_last_comment, post.comments.newest
  end

  def test_scopes_are_reset_on_association_reload
    post = posts(:welcome)

    [:destroy_all, :reset, :delete_all].each do |method|
      before = post.comments.containing_the_letter_e
      post.association(:comments).send(method)
      assert before.object_id != post.comments.containing_the_letter_e.object_id, "CollectionAssociation##{method} should reset the named scopes cache"
    end
  end

  def test_scoped_are_lazy_loaded_if_table_still_does_not_exist
    assert_nothing_raised do
      require "models/without_table"
    end
  end

  def test_eager_scopes_are_deprecated
    klass = Class.new(ActiveRecord::Base)
    klass.table_name = 'posts'

    assert_deprecated do
      klass.scope :welcome_2, klass.where(:id => posts(:welcome).id)
    end
    assert_equal [posts(:welcome).title], klass.welcome_2.map(&:title)
  end

  def test_eager_default_scope_relations_are_deprecated
    klass = Class.new(ActiveRecord::Base)
    klass.table_name = 'posts'

    assert_deprecated do
      klass.send(:default_scope, klass.where(:id => posts(:welcome).id))
    end
    assert_equal [posts(:welcome).title], klass.all.map(&:title)
  end
end