require 'net/ldap'

# handles the naughty bits of posix ldap
class LdapFluff::Posix::MemberService < LdapFluff::GenericMemberService
  def initialize(ldap, config)
    @attr_login = (config.attr_login || 'memberuid')
    @use_rfc4519_group_membership = config.use_rfc4519_group_membership
    super
  end

  def find_user(uid, base_dn = @base)
    user = @ldap.search(:filter => name_filter(uid), :base => base_dn)
    raise UIDNotFoundException if (user.nil? || user.empty?)
    user
  end

  # return an ldap user with groups attached
  # note : this method is not particularly fast for large ldap systems
  def find_user_groups(uid)
    user = find_user(uid).first
    groups = []
    @ldap.search(
      :filter => user_group_filter(uid, user[:dn].first),
      :base => @group_base, :attributes => ["cn"]
    ).each do |entry|
      groups << entry[:cn][0]
    end
    groups
  rescue UIDNotFoundException
    return []
  end

  def times_in_groups(uid, gids, all)
    filters = []
    gids.each do |cn|
      filters << group_filter(cn)
    end
    group_filters = merge_filters(filters, all)
    filter        = name_filter(uid) & group_filters
    @ldap.search(:base => @group_base, :filter => filter).size
  end

  # AND or OR all of the filters together
  def merge_filters(filters = [], all = false)
    if !filters.nil? && filters.size >= 1
      filter = filters[0]
      filters[1..(filters.size - 1)].each do |gfilter|
        filter = (all ? filter & gfilter : filter | gfilter)
      end
      filter
    end
  end

  class UIDNotFoundException < LdapFluff::Error
  end

  class GIDNotFoundException < LdapFluff::Error
  end

  private

  def user_group_filter(uid, user_dn)
    filter = Net::LDAP::Filter.eq('memberuid', uid)
    return filter unless @use_rfc4519_group_membership
    unique_filter = Net::LDAP::Filter.eq('uniquemember', user_dn) &
                    Net::LDAP::Filter.eq('objectClass', 'groupOfUniqueNames')
    filter | unique_filter
  end
end
