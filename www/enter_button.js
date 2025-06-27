$(document).keyup(function(event) {
  if ($("#prompt").is(":focus") && (event.key == "Enter")) {
    $("#submit").click();
  }
});