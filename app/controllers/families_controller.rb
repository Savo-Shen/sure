class FamiliesController < ApplicationController
  # Switching away from a stale tab is exactly how the user recovers from it.
  skip_before_action :reject_stale_ledger_write

  # Switches the session's active ledger (family). The target family must be
  # one the current user holds a membership in; RecordNotFound (rendered as a
  # 404) covers both a missing family and a non-membership so the endpoint
  # never reveals which families exist.
  def switch
    family = Current.user.families.find(params[:family_id])

    Current.session.switch_active_family!(family)

    redirect_to root_path, notice: t(".switched", family: family.name)
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: t(".not_a_member")
  end
end
