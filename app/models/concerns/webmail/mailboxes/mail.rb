module Webmail::Mailboxes::Mail
  def paginate_mails(options)
    Webmail::Mail.paginate(options.merge(select: name))
  end

  def paginate_mail_by_uid(uid, options)
    Webmail::Mail.paginate_by_uid(uid, options.merge(select: name))
  end

  def find_mails(options)
    Webmail::Mail.find(options.merge(select: name))
  end

  def find_mail_by_uid(uid, options)
    Webmail::Mail.find_by_uid(uid, options.merge(select: name))
  end

  def move_mails(dest_name, uids)
    Webmail::MailNode.delete_nodes(name, uids)
    Webmail::Mail.move_all(name, dest_name, uids)
  end

  def copy_mails(dest_name, uids)
    Webmail::Mail.copy_all(name, dest_name, uids)
  end

  def trash_mails(trash_name, uids)
    if trash_box?
      delete_mails(uids)
    else
      move_mails(trash_name, uids)
    end
  end

  def delete_mails(uids)
    Webmail::MailNode.delete_nodes(name, uids)
    Webmail::Mail.delete_all(name, uids)
  end

  def empty_mails
    imap.select(name)
    uids = imap.uid_search(['UNDELETED'], 'utf-8')
    delete_mails(uids)
  end

  def flag_mails(uids, flags)
    Webmail::Mail.flag_all(name, uids, flags)
  end

  def unflag_mails(uids, flags)
    Webmail::Mail.unflag_all(name, uids, flags)
  end

  def compress_mails(uids, options = {})
    Webmail::Mail.compress_mails(name, uids, options)
  end
end
