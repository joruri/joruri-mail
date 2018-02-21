require 'net/imap'
module Webmail::Mails::Imap
  extend ActiveSupport::Concern

  attr_accessor :uid, :mailbox, :flags, :rfc822, :size, :mail
  attr_accessor :priority, :x_mailbox, :x_real_uid

  def imap
    Core.imap
  end

  def parse(msg)
    begin
      @mail   = Mail::Message.new(msg)
      @rfc822 = msg
    rescue => e
      @mail   = Mail::Message.new
      @mail.subject = "#Error: #{e}"
    end
    self
  end

  def flags
    @flags || []
  end

  def seen?
    flags.index(:Seen)
  end

  def unseen?
    !seen?
  end

  def draft?
    flags.index(:Draft)
  end

  def answered?
    flags.index(:Answered)
  end

  def forwarded?
    flags.index('$Forwarded')
  end

  def starred?
    flags.index(:Flagged)
  end

  def mdn_sent?
    flags.index('$Notified') || flags.index('$MDNSent')
  end

  def labeled?(label_id = "")
    flags.index("$label#{label_id}")
  end

  def labels
    labels = flags.select { |flag| flag =~ /^\$label\d+$/ }
    labels.map { |flag| flag.gsub(/^\$label/, '') }.sort
  end

  def seen!
    @seen_flagged = true
    flags << :Seen
  end

  def seen_flagged?
    @seen_flagged
  end

  def destroy
    imap.select(mailbox)
    num = imap.uid_store(uid, '+FLAGS', [:Deleted]).to_a.size
    imap.expunge
    num == 1
  end

  def move(to_mailbox)
    return true if mailbox == to_mailbox

    imap.select(mailbox)
    num = self.class.move_to(to_mailbox, [uid])
    num == 1
  end

  class_methods do
    def imap
      Core.imap
    end

    def find_uids(select:, conditions: [], sort: nil)
      imap.examine(select) unless imap.opened?(select)
      if sort && imap.capabilities.include?('SORT')
        imap.uid_sort(sort, conditions, 'utf-8')
      else
        imap.uid_search(conditions, 'utf-8').reverse
      end
    end

    def find_by_uid(uid, select:, conditions: [], fetch: ['FLAGS', 'RFC822'])
      uid = uid.to_i
      return nil if uid == 0

      imap.examine(select) unless imap.opened?(select)
      search_uid = imap.uid_search(['UID', uid] + conditions, 'utf-8').first
      return nil unless search_uid

      fetch += ['X-MAILBOX', 'X-REAL-UID'] if select =~ /^virtual\./

      msg = imap.uid_fetch(search_uid, fetch).to_a.first
      return nil unless msg

      item = self.new
      item.parse(msg.attr['RFC822']) if msg.attr['RFC822']
      item.uid     = uid
      item.mailbox = select
      item.flags   = msg.attr['FLAGS'] if msg.attr['FLAGS']
      if select =~ /^virtual\./
        item.x_mailbox = msg.attr['X-MAILBOX']
        item.x_real_uid = msg.attr['X-REAL-UID']
      end
      item
    end

    def find(select:, conditions: [], sort: nil)
      imap.examine(select) unless imap.opened?(select)
      uids =
        if sort && imap.capabilities.include?('SORT')
          imap.uid_sort(sort, conditions, 'utf-8')
        else
          imap.uid_search(conditions, 'utf-8')
        end

      items = fetch(uids, select)
      items.sort { |a, b| uids.index(a.uid) <=> uids.index(b.uid) }
    end

    def paginate(select:, conditions: [], sort: [], page: 1, limit: 20, starred: nil)
      page = (page.presence || 1).to_i
      limit = (limit.presence || 20).to_i

      uids, total_count =
        if imap.capabilities.include?('ESORT') && starred != '1'
          paginate_uids_by_esort(select: select, conditions: conditions, sort: sort, page: page, limit: limit)
        else
          paginate_uids_by_sort(select: select, conditions: conditions, sort: sort, page: page, limit: limit, starred: starred)
        end

      items = fetch(uids, select)
      items.sort! { |a, b| uids.index(a.uid) <=> uids.index(b.uid) }

      WillPaginate::Collection.create(page, limit, total_count) do |pager|
        pager.replace(items)
      end
    end

    def paginate_by_uid(uid, select:, conditions: [], sort: [], starred: nil)
      uids =
        if starred == '1'
          find_uids(select: select, conditions: conditions + ['FLAGGED'], sort: sort) +
          find_uids(select: select, conditions: conditions + ['UNFLAGGED'], sort: sort)
        else
          find_uids(select: select, conditions: conditions, sort: sort)
        end

      idx = uids.index(uid.to_i)
      attr = {}
      attr[:total_items]  = uids.size
      attr[:prev_uid]     = uids[idx - 1] if idx && idx > 0
      attr[:next_uid]     = uids[idx + 1] if idx &&idx < uids.size - 1
      attr[:current_page] = idx + 1 if idx
      attr
    end

    def fetch(uids, mailbox, options = {})
      items = options[:items] || []
      return items if uids.blank?

      imap.examine(mailbox) unless imap.opened?(mailbox)

      uids   = [uids] if uids.class == Fixnum
      fields = ["UID", "FLAGS", "RFC822.SIZE", "BODY.PEEK[HEADER.FIELDS (DATE FROM TO SUBJECT CONTENT-TYPE)]"]
      msgs   = imap.uid_fetch(uids, fields)
      msgs.each do |msg|
        item = self.new
        item.parse(msg.attr["BODY[HEADER.FIELDS (DATE FROM TO SUBJECT CONTENT-TYPE)]"])
        item.uid     = msg.attr["UID"].to_i
        item.mailbox = mailbox
        item.size    = msg.attr['RFC822.SIZE']
        item.flags   = msg.attr["FLAGS"]
        items << item
      end if msgs.present?
      items
    end

    def fetch_each(uids, mailbox)
      uids = Array(uids)
      return [] if uids.blank?

      imap.examine(mailbox) unless imap.opened?(mailbox)

      uids.each_slice(10) do |sliced_uids|
        items = imap.uid_fetch(sliced_uids, ['UID', 'RFC822']).to_a.map do |msg|
                  item = self.new(msg.attr['RFC822'])
                  item.uid     = msg.attr['UID'].to_i
                  item.mailbox = mailbox
                  item
                end
        items.each { |item| yield item }
      end
    end

    def move_all(from_mailbox, to_mailbox, uids)
      return 0 if from_mailbox == to_mailbox
      return 0 if uids.size == 0

      imap.select(from_mailbox)
      move_to(to_mailbox, uids)
    end

    def copy_all(from_mailbox, to_mailbox, uids)
      return 0 if uids.blank?

      imap.select(from_mailbox)
      res = imap.uid_copy(uids, to_mailbox)
      res.name == 'OK' ? uids.size : 0
    end

    def delete_all(mailbox, uids)
      return 0 if uids.blank?

      imap.select(mailbox)
      num = imap.uid_store(uids, '+FLAGS', [:Deleted]).to_a.size
      imap.expunge
      num
    end

    def flag_all(mailbox, uids, flags)
      imap.select(mailbox)
      imap.uid_store(uids, '+FLAGS', flags).to_a.size
    end

    def unflag_all(mailbox, uids, flags)
      imap.select(mailbox)
      imap.uid_store(uids, '-FLAGS', flags).to_a.size
    end

    def move_to(mailbox, uids)
      if imap.capabilities.include?('MOVE')
        move_to_by_move(mailbox, uids)
      else
        move_to_by_copy(mailbox, uids)
      end
    end

    def compress_mails(mailbox, uids, encoding: 'shift_jis')
      zip = ""
      count = 0
      Zip::Archive.open_buffer(zip, Zip::CREATE) do |ar|
        fetch_each(uids, mailbox) do |mail|
          begin
            count += 1
            filename = "#{mail.filename_for_download}.eml"
            filename = filename.encode(encoding, undef: :replace, invalid: :replace, replace: '_')
            ar.add_buffer(filename, mail.rfc822)
          rescue Zip::Error => e
            error_log e
          end
        end
      end
      return zip, count
    end

    private

    def paginate_uids_by_esort(select:, conditions:, sort:, page:, limit:)
      st = limit * (page - 1) + 1
      ed = limit * page

      imap.select(select)
      ret = imap.uid_esort(sort, conditions, 'utf-8', "PARTIAL #{st}:#{ed} COUNT")
      if st > ret['COUNT']
        return [], ret['COUNT']
      else
        return ret['PARTIAL'], ret['COUNT']
      end
    end

    def paginate_uids_by_sort(select:, conditions:, sort:, page:, limit:, starred:)
      offset = [0, page - 1].max * limit

      imap.select(select)
      total_uids =
        if starred == '1'
          find_uids(select: select, conditions: conditions + ['FLAGGED'], sort: sort) +
          find_uids(select: select, conditions: conditions + ['UNFLAGGED'], sort: sort)
        else
          find_uids(select: select, conditions: conditions, sort: sort)
        end
      page_uids = total_uids.slice(offset, limit).to_a
      return page_uids, total_uids.size
    end

    def move_to_by_move(mailbox, uids)
      res = imap.uid_move(uids, mailbox)
      res.name == 'OK' ? uids.size : 0
    end

    def move_to_by_copy(mailbox, uids)
      res = imap.uid_copy(uids, mailbox)
      if res.name == 'OK'
        num = imap.uid_store(uids, "+FLAGS", [:Deleted]).to_a.size
        imap.expunge
        num
      else
        0
      end
    end
  end
end
