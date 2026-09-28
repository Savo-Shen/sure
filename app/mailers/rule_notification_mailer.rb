class RuleNotificationMailer < ApplicationMailer
  def digest(rule:, transactions:)
    @rule = rule
    @transactions = transactions
    @family = rule.family
    @transactions_url = transactions_url

    # Admins only: the digest contains transaction details, so never widen the
    # recipient set to an editor/viewer. Owners and admins of this ledger
    # qualify, whichever ledger is their primary one. Skip delivery entirely
    # when there is no admin.
    recipient = @family.family_memberships.by_privilege
                       .find_by(role: %w[owner admin])&.user
    return if recipient.nil?

    mail(
      to: recipient.email,
      subject: t(".subject", count: transactions.size, product_name: product_name)
    )
  end
end
