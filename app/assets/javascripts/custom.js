$(document).on('turbolinks:load', function(){
  const notify = (selector) => {
    let obj = $(selector);
    if(obj.text().length > 0) {
      obj.show();
      setTimeout(function(){
        obj.fadeOut('slow');
      },10000);
    }

    obj.click(function(){
      $(this).fadeOut('slow');
    });
  };
  notify('.notice');
  notify('.alert');

  $('#btn-notes').click(function() {
    $('#notes').val($('#notes_field').val());
    $('#notesModal').modal('hide');
  });
});
