"use client"; // or remove if using pages/

import React, { useState, useEffect } from "react";
import { getProducts, createProduct } from "../lib/api";

export default function Home() {
  const [products, setProducts] = useState([]);
  const [form, setForm] = useState({ name: "", price: "", image: null });
  console.log("api_url: ", process.env.NEXT_PUBLIC_API_URL);
  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    const res = await getProducts();
    setProducts(res.data);
  };

  const handleChange = (e) => {
    const { name, value, files } = e.target;
    setForm({
      ...form,
      [name]: files ? files[0] : value,
    });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const data = new FormData();
    data.append("name", form.name);
    data.append("price", form.price);
    if (form.image) data.append("image", form.image);

    await createProduct(data);
    setForm({ name: "", price: "", image: null });
    fetchProducts();
  };

  return (
    <div style={{ padding: 20 }}>
      <h2 className="text-2xl font-bold text-center mt-5 mb-3">Add Product</h2>
      <form onSubmit={handleSubmit} className="flex justify-around">
        <input
          type="text"
          name="name"
          placeholder="Name"
          onChange={handleChange}
          required
        />
        <input
          type="number"
          name="price"
          placeholder="Price"
          onChange={handleChange}
          required
        />
        <input type="file" name="image" onChange={handleChange} />
        <button type="submit">Create</button>
      </form>

      <hr className="my-4" />
      <h2>Products</h2>
      <ul>
        {products.map((p) => (
          <li key={p.id}>
            {p.name} - ${p.price}
            {p.image && <img src={p.image} alt={p.name} width="100" />}
          </li>
        ))}
      </ul>
    </div>
  );
}
