'use strict';

// card / table toggle
const viewCards = document.getElementById('viewCards');
const viewTable = document.getElementById('viewTable');
const cardsContainer = document.getElementById('cardsContainer');
const tableContainer = document.getElementById('tableContainer');

if (viewCards && viewTable) {
  const PREF_KEY = 'rv_view';
  const pref = localStorage.getItem(PREF_KEY);
  if (pref === 'table') {
    cardsContainer.classList.add('d-none');
    tableContainer.classList.remove('d-none');
    viewCards.classList.remove('active');
    viewTable.classList.add('active');
  }

  viewCards.addEventListener('click', () => {
    cardsContainer.classList.remove('d-none');
    tableContainer.classList.add('d-none');
    viewCards.classList.add('active');
    viewTable.classList.remove('active');
    localStorage.setItem(PREF_KEY, 'cards');
  });

  viewTable.addEventListener('click', () => {
    cardsContainer.classList.add('d-none');
    tableContainer.classList.remove('d-none');
    viewTable.classList.add('active');
    viewCards.classList.remove('active');
    localStorage.setItem(PREF_KEY, 'table');
  });
}

// favorite buttons on listings page
document.querySelectorAll('.fav-btn').forEach(btn => {
  btn.addEventListener('click', e => {
    e.preventDefault();
    e.stopPropagation();
    const id = btn.dataset.id;
    fetch(`/listing/${id}/favorite`, { method: 'POST' })
      .then(r => r.json())
      .then(data => {
        const icon = btn.querySelector('i');
        if (icon) {
          icon.className = data.is_favorite ? 'bi bi-star-fill text-warning' : 'bi bi-star';
        }
      })
      .catch(console.error);
  });
});

// auto-submit filter form on select change (desktop convenience)
const filterForm = document.getElementById('filterForm');
if (filterForm) {
  filterForm.querySelectorAll('select').forEach(sel => {
    sel.addEventListener('change', () => filterForm.submit());
  });
}
