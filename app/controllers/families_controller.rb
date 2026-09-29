class FamiliesController < ApplicationController
  # Switching away from a stale tab is exactly how the user recovers from it,
  # and creating a ledger writes nothing into the active one. Neither action
  # can land data in the wrong ledger, so the stale-write guard is skipped.
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

  def new
    @family = Family.new(inherited_settings)
  end

  def create
    @family = Family.new(inherited_settings.merge(family_params.to_h))

    if @family.save
      # The creator owns the ledger they just made, independent of their role in
      # the ledger they came from, and lands in it right away.
      Current.user.family_memberships.create!(family: @family, role: "owner")
      Current.session.switch_active_family!(@family)

      redirect_to root_path, notice: t(".created", family: display_name_for(@family))
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    # The form only offers the currencies the active ledger has enabled, so a
    # currency from outside that list means the request didn't come from the
    # form. Dropping it (rather than rejecting everything) falls back to the
    # inherited or default currency.
    def family_params
      permitted = params.require(:family).permit(:name, :currency)

      currency = Family.normalize_currency_code(permitted[:currency])
      permitted.delete(:currency) unless currency.in?((Current.family || Family.new).enabled_currency_codes)

      permitted
    end

    # A new ledger starts from the regional and formatting settings of the one
    # the user is currently in, so they don't have to pick a currency, a date
    # format and a timezone all over again. Content, sharing and money settings
    # keep their defaults.
    def inherited_settings
      source = Current.family
      return {} unless source

      {
        currency: source.currency,
        country: source.country,
        locale: source.locale,
        date_format: source.date_format,
        timezone: source.timezone,
        month_start_day: source.month_start_day
      }
    end

    def display_name_for(family)
      family.name.presence || t("families.switcher.unnamed_ledger")
    end
end
