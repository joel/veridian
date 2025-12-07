require "rails_helper"

RSpec.describe "posts/edit" do
  let(:post) do
    create(:post)
  end

  let!(:user) { create(:user) }

  before do
    assign(:post, post)
  end

  it "renders the edit post form" do
    render

    assert_select "form[action=?][method=?]", post_path(post), "post" do
      assert_select "input[name=?]", "post[title]"

      assert_select "textarea[name=?]", "post[body]"

      assert_select "select[name=?]", "post[user_id]"
    end
  end
end
